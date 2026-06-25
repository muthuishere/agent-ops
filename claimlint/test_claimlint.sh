#!/usr/bin/env bash
# Tests for claimlint — flags agent completion CLAIMS that the session's own
# tool-records (and optionally the filesystem) contradict. Deterministic, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CL="$HERE/claimlint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/cl.XXXXXX; }

# --- T1: claims tests pass, but no test run succeeded => TEST-CLAIM, exit 1
f=$(tmp)
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All 12 tests pass. The build is clean and green."}]}}\n' > "$f"
o=$("$CL" --transcript "$f" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "TEST-CLAIM"; } && ok "T1 false test-pass claim flagged" || bad "T1" "$o (rc=$rc)"

# --- T2: independence — the checker reads tool RECORDS, not the agent's narration.
# A claim that tests pass IS supported when a test runner actually succeeded.
f2=$(tmp)
printf '%s\n' \
'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"p1","name":"Bash","input":{"command":"pytest -q"}}]}}' \
'{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"p1","content":"12 passed in 0.4s"}]}}' \
'{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass."}]}}' > "$f2"
o=$("$CL" --transcript "$f2" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T2 claim backed by a real successful test run passes" || bad "T2" "$o (rc=$rc)"

# --- T3: claims it created a file, but no Edit/Write tool call (and not on disk) => FILE-CLAIM
f3=$(tmp)
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I created src/auth_handler_xyz.py with the new login flow."}]}}\n' > "$f3"
o=$("$CL" --transcript "$f3" --root /tmp 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "FILE-CLAIM"; } && ok "T3 unsupported file-creation claim flagged" || bad "T3" "$o (rc=$rc)"

# --- T4: a transcript with no victory claims => clean, exit 0
f4=$(tmp)
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Here is how the function works and what it returns."}]}}\n' > "$f4"
o=$("$CL" --transcript "$f4" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T4 no-claim transcript passes" || bad "T4" "$o (rc=$rc)"

rm -f "$f" "$f2" "$f3" "$f4"
echo "----"; echo "claimlint: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
