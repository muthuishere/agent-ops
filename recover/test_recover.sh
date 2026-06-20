#!/usr/bin/env bash
# Test harness for the `recover` spike. Each test builds a fresh throwaway repo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RECOVER="$HERE/recover"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# newrepo prints the dir; caller must `cd "$(newrepo)"` so cd lands in THIS shell.
newrepo() {
  local d; d=$(mktemp -d /tmp/recover-test.XXXXXX)
  ( cd "$d"; git init -q
    git config user.email t@t.com; git config user.name T
    echo base > f.txt; git add f.txt; git commit -q -m base ) >/dev/null
  echo "$d"
}

# --- Test 1: lost via worktree-remove + branch delete IS recoverable ---
cd "$(newrepo)"
git worktree add -q wt -b feat
( cd wt; git config user.email t@t.com; git config user.name T
  echo work > w.txt; git add w.txt; git commit -q -m "lost via worktree" )
SHA=$(git -C wt rev-parse HEAD)
git worktree remove --force wt; git branch -D feat >/dev/null; git worktree prune
L=$("$RECOVER" list); echo "$L" | grep -q "$(git rev-parse --short "$SHA")" && ok "T1 worktree-remove listed" || bad "T1 worktree-remove listed"
"$RECOVER" to got "$SHA" >/dev/null
[ "$(git rev-parse got 2>/dev/null)" = "$SHA" ] && ok "T1 restored to branch" || bad "T1 restored to branch"

# --- Test 2: lost via reset --hard IS recoverable ---
cd "$(newrepo)"
echo more >> f.txt; git add f.txt; git commit -q -m "lost via reset"
SHA=$(git rev-parse HEAD)
git reset --hard HEAD~1 >/dev/null
git reflog expire --expire=now --all   # make it truly dangling
L=$("$RECOVER" list); echo "$L" | grep -q "$(git rev-parse --short "$SHA")" && ok "T2 reset listed" || bad "T2 reset listed"
"$RECOVER" to got2 "$SHA" >/dev/null
[ "$(git rev-parse got2 2>/dev/null)" = "$SHA" ] && ok "T2 restored" || bad "T2 restored"

# --- Test 3: after gc --prune=now NOT listed and restore fails ---
cd "$(newrepo)"
echo doomed >> f.txt; git add f.txt; git commit -q -m "doomed"
SHA=$(git rev-parse HEAD)
git reset --hard HEAD~1 >/dev/null
git reflog expire --expire=now --all
git gc --prune=now -q
L=$("$RECOVER" list); echo "$L" | grep -q "${SHA:0:7}" && bad "T3 should be gone after gc" || ok "T3 not listed after gc --prune=now"
"$RECOVER" to nope "$SHA" >/dev/null 2>&1 && bad "T3 restore should fail" || ok "T3 restore fails after gc"

# --- Test 4: uncommitted (never staged) work in rm -rf'd worktree NOT recoverable ---
cd "$(newrepo)"
git worktree add -q wt4
( cd wt4; echo "unsaved" >> f.txt; echo new > brandnew.txt )   # never git add
rm -rf wt4; git worktree prune
out=$("$RECOVER" list)
echo "$out" | grep -q "no dangling commits" && ok "T4 uncommitted work not recoverable (list empty)" || bad "T4 should report nothing (got: $out)"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
