#!/usr/bin/env bash
# Tests for auto-snapshot — fresh throwaway repos; covers the untracked-file case
# (the whole point), recoverability, no-op on clean, gc-survival, and the CLI.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AS="$HERE/auto-snapshot"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
newrepo() {
  local d; d=$(mktemp -d /tmp/auto-snap.XXXXXX)
  ( cd "$d"; git init -q; git config user.email t@t.com; git config user.name T
    echo base > tracked.txt; git add tracked.txt; git commit -q -m base ) >/dev/null
  echo "$d"
}

# --- T1+T2: untracked file AND tracked edit are captured and recoverable ---
R=$(newrepo); cd "$R"
echo "agent's new file" > new.js          # untracked — git stash create would MISS this
echo "agent's edit" >> tracked.txt        # tracked change
echo '{"hook_event_name":"Stop"}' | "$AS" >/dev/null 2>&1
# simulate the loss
rm new.js; git checkout -- tracked.txt
"$AS" restore latest >/dev/null 2>&1
[ -f new.js ] && grep -q "agent's new file" new.js && ok "T1 recovers an UNTRACKED file" || bad "T1 untracked" "new.js: $(cat new.js 2>&1)"
grep -q "agent's edit" tracked.txt && ok "T2 recovers a tracked edit" || bad "T2 tracked" "$(cat tracked.txt)"

# --- T3: snapshot does not touch the working tree ---
R=$(newrepo); cd "$R"; echo dirty >> tracked.txt; echo new > x.txt
before=$(git status --porcelain); echo '{}' | "$AS" >/dev/null 2>&1; after=$(git status --porcelain)
[ "$before" = "$after" ] && ok "T3 working tree/index untouched by snapshot" || bad "T3 untouched" "changed"

# --- T4: clean repo is a no-op (no ref created) ---
R=$(newrepo); cd "$R"
echo '{}' | "$AS" >/dev/null 2>&1
[ -z "$(git for-each-ref refs/wip-snapshots/)" ] && ok "T4 clean repo = no snapshot" || bad "T4 clean" "ref created"

# --- T5: list shows a taken snapshot ---
R=$(newrepo); cd "$R"; echo z > z.txt; echo '{}' | "$AS" >/dev/null 2>&1
"$AS" list | grep -Eq "\[main\]" && ok "T5 list shows the snapshot" || bad "T5 list" "$("$AS" list)"

# --- T6: restore by short-sha prefix ---
R=$(newrepo); cd "$R"; echo q > q.txt; out=$(echo '{}' | "$AS" 2>&1); sha=$(echo "$out" | grep -oE 'saved [0-9a-f]+' | awk '{print $2}')
rm q.txt; "$AS" restore "$sha" >/dev/null 2>&1
[ -f q.txt ] && ok "T6 restore by sha prefix" || bad "T6 restore sha" "no q.txt"

# --- T7: the snapshot survives gc --prune=now (ref-pinned) ---
R=$(newrepo); cd "$R"; echo keep > keep.txt; out=$(echo '{}' | "$AS" 2>&1); sha=$(echo "$out" | grep -oE 'saved [0-9a-f]+' | awk '{print $2}')
git gc --prune=now -q 2>/dev/null
git cat-file -e "$sha" 2>/dev/null && ok "T7 snapshot survives gc --prune=now" || bad "T7 gc" "gone after gc"

# --- T8: not-a-git-repo: hook=exit0 silent, CLI=exit2 ---
D=$(mktemp -d); cd "$D"
echo '{}' | "$AS" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8 hook no-ops outside a repo (exit 0)" || bad "T8 hook outside" "nonzero"
"$AS" list >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T8 CLI errors outside a repo (exit 2)" || bad "T8 cli outside" "not 2"

# --- T9: prune --keep keeps the newest N ---
R=$(newrepo); cd "$R"
for i in 1 2 3 4; do echo "v$i" > f.txt; echo '{}' | "$AS" >/dev/null 2>&1; sleep 1; done
"$AS" prune --keep 2 >/dev/null 2>&1
[ "$(git for-each-ref refs/wip-snapshots/ | wc -l | tr -d ' ')" -eq 2 ] && ok "T9 prune --keep 2 keeps two" || bad "T9 prune" "$(git for-each-ref refs/wip-snapshots/ | wc -l)"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
