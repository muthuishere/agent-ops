#!/usr/bin/env bash
# Tests for agent-guard — feed synthetic PreToolUse JSON on stdin, assert the
# hook denies destructive commands and stays out of the way otherwise.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/agent-guard"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

inp() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2"; }

# assert_deny "<label>" "<command>"
assert_deny() {
  local out; out=$(inp Bash "$2" | "$GUARD")
  echo "$out" | grep -q '"deny"' && ok "$1" || bad "$1" "expected deny, got: ${out:-<empty>}"
}
# assert_allow "<label>" "<command>"
assert_allow() {
  local out; out=$(inp Bash "$2" | "$GUARD")
  [ -z "$out" ] && ok "$1" || bad "$1" "expected allow (empty), got: $out"
}

echo "### blocks the catastrophic"
assert_deny  "git reset --hard"            "git reset --hard HEAD~2"
assert_deny  "reset --hard mid-chain"      "cd src && git reset --hard origin/main"
assert_deny  "git clean -fd"               "git clean -fd"
assert_deny  "git push --force"            "git push --force origin main"
assert_deny  "git branch -D"               "git branch -D feature/x"
assert_deny  "git checkout -- ."           "git checkout -- ."
assert_deny  "git restore ."               "git restore ."
assert_deny  "git stash drop"              "git stash drop"
assert_deny  "git worktree remove --force" "git worktree remove --force ../wt"
assert_deny  "rm -rf"                       "rm -rf build/"
assert_deny  "rm -r -f (split flags)"       "rm -r -f node_modules"

echo "### allows the safe equivalents"
assert_allow "git reset --soft"            "git reset --soft HEAD~1"
assert_allow "git clean -n (preview)"      "git clean -n"
assert_allow "git push --force-with-lease" "git push --force-with-lease origin main"
assert_allow "git branch -d (safe delete)" "git branch -d merged-branch"
assert_allow "git restore --staged"        "git restore --staged file.txt"
assert_allow "git checkout -b"             "git checkout -b feature/y"
assert_allow "ordinary commands"           "git status && npm test"
assert_allow "rm a single file"            "rm stale.log"

echo "### scope + safety"
# non-Bash tools are never the hook's business
ne=$(python3 -c 'import json; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"x","old_string":"a","new_string":"b"}}))' | "$GUARD")
[ -z "$ne" ] && ok "non-Bash tool ignored" || bad "non-Bash tool ignored" "$ne"
# escape hatch
eh=$(AGENT_GUARD_OFF=1; export AGENT_GUARD_OFF; inp Bash "git reset --hard" | "$GUARD")
[ -z "$eh" ] && ok "AGENT_GUARD_OFF=1 bypasses" || bad "AGENT_GUARD_OFF bypass" "$eh"
# fail safe on garbage stdin
fs=$(printf 'not json at all' | "$GUARD")
[ -z "$fs" ] && ok "malformed stdin fails safe (allow)" || bad "malformed stdin" "$fs"
# the deny payload carries a reason
dr=$(inp Bash "git reset --hard HEAD" | "$GUARD")
echo "$dr" | grep -q '"permissionDecisionReason"' && echo "$dr" | grep -q "Safer:" && ok "deny includes a reason + safer alternative" || bad "deny reason" "$dr"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
