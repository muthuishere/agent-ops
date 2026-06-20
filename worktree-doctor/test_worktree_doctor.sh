#!/usr/bin/env bash
# Tests for worktree-doctor — builds a throwaway repo with a real bare remote and
# worktrees in known states (pushed-clean, dirty, unpushed), asserts the flags.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WD="$HERE/worktree-doctor"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
gc() { git -c user.email=t@t.com -c user.name=T "$@"; }

ROOT=$(mktemp -d /tmp/wt-doctor.XXXXXX)
BARE="$ROOT/origin.git"; MAIN="$ROOT/main"
git init -q --bare "$BARE"
git init -q "$MAIN"; cd "$MAIN"
git remote add origin "$BARE"
echo base > f.txt; gc add f.txt; gc commit -qm base
gc push -q -u origin HEAD:refs/heads/main
gc branch -q -M main

# wt-clean: a branch that IS pushed -> safe
gc worktree add -q "$ROOT/wt-clean" -b pushed
( cd "$ROOT/wt-clean"; echo a > a.txt; gc add a.txt; gc commit -qm a; gc push -q -u origin pushed )
# wt-dirty: uncommitted changes -> at risk
gc worktree add -q "$ROOT/wt-dirty" -b dirtybr
( cd "$ROOT/wt-dirty"; echo uncommitted >> f.txt )   # never committed
# wt-unpushed: a commit that was never pushed -> at risk
gc worktree add -q "$ROOT/wt-unpushed" -b localonly
( cd "$ROOT/wt-unpushed"; echo b > b.txt; gc add b.txt; gc commit -qm "local only" )

cd "$MAIN"; gc fetch -q origin   # make remote-tracking refs current
out=$("$WD" 2>/dev/null); rc=$?

echo "### detection"
echo "$out" | grep -q "4 worktrees" && ok "T1 finds all 4 worktrees" || bad "T1 count" "$out"
echo "$out" | grep -Eq "wt-dirty.*uncommitted changes" && ok "T2 flags dirty worktree" || bad "T2 dirty" "$out"
echo "$out" | grep -Eq "wt-unpushed.*1 commit\(s\) on no remote" && ok "T3 flags the unpushed commit" || bad "T3 unpushed" "$out"
echo "$out" | grep -Eq "wt-clean.*safe" && ok "T4 pushed+clean worktree is safe" || bad "T4 safe" "$out"

echo "### risk summary + exit code"
echo "$out" | grep -q "at risk" && ok "T5 prints at-risk summary" || bad "T5 summary" "$out"
[ "$rc" -eq 1 ] && ok "T6 exit 1 when a worktree is at risk" || bad "T6 exit code" "got $rc"

echo "### --quiet"
q=$("$WD" --quiet 2>/dev/null)
echo "$q" | grep -q "wt-dirty" && ! echo "$q" | grep -q "wt-clean" && ok "T7 --quiet shows only at-risk" || bad "T7 quiet" "$q"

echo "### all-safe case -> exit 0"
( cd "$ROOT/wt-dirty"; gc checkout -q -- f.txt )         # undo the dirt
( cd "$ROOT/wt-unpushed"; gc push -q -u origin localonly )  # push the commit
cd "$MAIN"; gc fetch -q origin
"$WD" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8 exit 0 once everything is committed+pushed" || bad "T8 all-safe exit" "expected 0"

rm -rf "$ROOT"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
