#!/usr/bin/env bash
# Test harness for ./preflight — builds a throwaway repo and exercises the
# five cases the merge-tree spike verified by hand. Test-first: written before
# the script, run after, must be green.
#
#   1. clean / different files          -> CLEAR  (exit 0)
#   2. same file, DIFFERENT lines       -> CLEAR  (exit 0)   <- the headline case
#   3. same file, SAME lines            -> CONFLICT (exit 1) lists the file
#   4. dirty working tree candidate     -> CONFLICT (exit 1) via --working
#   5. bad ref                          -> ERROR (exit 2), NOT mistaken for conflict
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT="$HERE/preflight"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; echo "       $2"; }

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"
git init -q
git config user.email t@t.t; git config user.name t
printf 'line1\nline2\nline3\nline4\nline5\n' > app.txt
git add -A; git commit -qm base
BASE=$(git rev-parse HEAD)

branch() { # branch <name> <file> <content...>
  git checkout -q -b "$1" "$BASE"; shift
  local f="$1"; shift; printf '%s\n' "$@" > "$f"
  git add -A; git commit -qm "$f"
  git checkout -q "$BASE"
}
branch agentA app.txt   line1 line2 LINE3-A line4 line5    # edits line3
branch agentB app.txt   line1 line2 LINE3-B line4 line5    # edits line3 too
branch agentC app.txt   line1 line2 LINE3-C line4 line5    # edits line3
branch agentD other.txt hello                              # new file, no app.txt touch
branch agentE app.txt   LINE1-E line2 line3 line4 line5    # edits line1
branch agentF app.txt   line1 line2 line3 line4 LINE5-F    # edits line5

# --- 1. clean: different files (agentC edits app.txt, agentD adds other.txt) ---
out=$("$PREFLIGHT" agentC agentD); rc=$?
{ [ $rc -eq 0 ] && [ "$out" = "CLEAR" ]; } \
  && ok "different files -> CLEAR" \
  || bad "different files -> CLEAR" "rc=$rc out=[$out]"

# --- 2. clean: same file, different lines (agentE line1 vs agentF line5) ---
out=$("$PREFLIGHT" agentE agentF); rc=$?
{ [ $rc -eq 0 ] && [ "$out" = "CLEAR" ]; } \
  && ok "same file / different lines -> CLEAR (line-aware)" \
  || bad "same file / different lines -> CLEAR" "rc=$rc out=[$out]"

# --- 3. conflict: same file, same lines (agentA vs agentB) ---
out=$("$PREFLIGHT" agentA agentB); rc=$?
{ [ $rc -eq 1 ] && printf '%s' "$out" | grep -q '^CONFLICT$' \
    && printf '%s' "$out" | grep -q '^app.txt$'; } \
  && ok "same file / same lines -> CONFLICT + lists app.txt" \
  || bad "same file / same lines -> CONFLICT" "rc=$rc out=[$out]"

# --- 4. dirty working tree candidate via --working ---
git checkout -q agentB           # HEAD has the conflicting line3 edit committed
git checkout -q -b work-dirty agentA
printf 'line1\nline2\nDIRTY3\nline4\nline5\n' > app.txt   # uncommitted, conflicts w/ agentB
out=$("$PREFLIGHT" --working agentB); rc=$?
{ [ $rc -eq 1 ] && printf '%s' "$out" | grep -q '^CONFLICT$' \
    && printf '%s' "$out" | grep -q '^app.txt$'; } \
  && ok "dirty working tree candidate -> CONFLICT (snapshot path)" \
  || bad "dirty working tree candidate -> CONFLICT" "rc=$rc out=[$out]"
git checkout -q -- app.txt; git checkout -q "$BASE"

# --- 5. bad ref -> ERROR (exit 2), not a false conflict ---
out=$("$PREFLIGHT" agentA no-such-ref 2>/dev/null); rc=$?
[ $rc -eq 2 ] \
  && ok "bad ref -> exit 2 (not mistaken for conflict)" \
  || bad "bad ref -> exit 2" "rc=$rc out=[$out]"

echo "-----"
echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
