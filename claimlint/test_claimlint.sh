#!/usr/bin/env bash
# Tests for claimlint — flags completion CLAIMS the session + filesystem contradict.
# Deterministic + offline: synthetic JSONL transcripts where the agent's victory claim
# either is, or is not, backed by a real tool-call record (and optionally the disk).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CL="$HERE/claimlint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

D=$(mktemp -d /tmp/claimlint.XXXXXX)

# --- T1/T2: TEST-CLAIM — "all tests pass" but NO test runner ever ran -> unsupported
cat > "$D/notests.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"e1","input":{"file_path":"/x/foo.py","old_string":"a","new_string":"b"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. All tests pass and the suite is green."}]}}
JSON
"$CL" "$D/notests.jsonl" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T1 unsupported test-claim => exit 1" || bad "T1 notests exit" "rc"
o=$("$CL" "$D/notests.jsonl" 2>&1); echo "$o" | grep -q "TEST-CLAIM" && ok "T2 reports TEST-CLAIM" || bad "T2 notests" "$o"

# --- T3 (LOAD-BEARING): "all tests pass" IS supported when pytest actually ran + passed
cat > "$D/ranok.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"b1","input":{"command":"pytest -q"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":false,"content":"5 passed in 0.4s"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass."}]}}
JSON
"$CL" "$D/ranok.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T3 supported test-claim is clean (exit 0)" || bad "T3 ranok exit" "rc"

# --- T4: a test run that ERRORED does not support a pass-claim -> TEST-CLAIM
cat > "$D/ranfail.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"b1","input":{"command":"pytest -q"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"2 failed, 3 passed"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass now."}]}}
JSON
o=$("$CL" "$D/ranfail.jsonl" 2>&1); echo "$o" | grep -q "TEST-CLAIM" && ok "T4 failed run => claim still unsupported" || bad "T4 ranfail" "$o"

# --- T5: FUTURE/INTENT phrasing is not an assertion -> not flagged
cat > "$D/future.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Next I will run the tests to make sure all tests pass."}]}}
JSON
"$CL" "$D/future.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T5 future/intent phrasing not flagged" || bad "T5 future exit" "rc"

# --- T6/T7: FILE-CLAIM — claims it created a file with NO edit tool call -> unsupported
cat > "$D/nofile.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I created src/auth/login.py with the handler."}]}}
JSON
"$CL" "$D/nofile.jsonl" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T6 unsupported file-claim => exit 1" || bad "T6 nofile exit" "rc"
o=$("$CL" "$D/nofile.jsonl" 2>&1); echo "$o" | grep -q "FILE-CLAIM" && ok "T7 reports FILE-CLAIM" || bad "T7 nofile" "$o"

# --- T8: FILE-CLAIM IS supported when a Write/Edit tool call touched that path
cat > "$D/yesfile.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","id":"w1","input":{"file_path":"src/auth/login.py","content":"x"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I created src/auth/login.py with the handler."}]}}
JSON
"$CL" "$D/yesfile.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8 file-claim backed by Write is clean" || bad "T8 yesfile exit" "rc"

# --- T9: --root verifies a claimed file that exists on disk even without an edit call
mkdir -p "$D/repo/docs"; printf 'hi\n' > "$D/repo/docs/readme-extra.md"
cat > "$D/ondisk.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I added docs/readme-extra.md to the repo."}]}}
JSON
"$CL" --root "$D/repo" "$D/ondisk.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T9 --root accepts a file present on disk" || bad "T9 ondisk exit" "rc"
# ... and without --root (and no edit call) the same claim is unsupported
"$CL" "$D/ondisk.jsonl" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T10 same claim unsupported without --root" || bad "T10 noroot exit" "rc"

# --- T11: a genuinely honest final message -> clean + supportive wording
cat > "$D/honest.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"b1","input":{"command":"go test ./..."}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":false,"content":"ok  example  0.2s"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Tests pass; nothing else to change."}]}}
JSON
"$CL" "$D/honest.jsonl" 2>&1 | grep -qi "clean" && ok "T11 honest session reported clean" || bad "T11 honest" "$("$CL" "$D/honest.jsonl")"

# --- T12: --json is machine-readable
o=$("$CL" --json "$D/notests.jsonl" 2>&1)
echo "$o" | grep -q '"check"' && ok "T12 --json emits findings" || bad "T12 json" "$o"
echo "$o" | grep -q '"clean": false' && ok "T13 --json marks unsupported as not clean" || bad "T13 json clean" "$o"

# --- T14: not a transcript at all -> exit 2
printf 'plain text, not a session\n' > "$D/plain.txt"
"$CL" "$D/plain.txt" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T14 non-transcript exits 2" || bad "T14 plain exit" "rc"

# --- T15: --all scans every assistant message, catching a mid-session false claim
cat > "$D/midclaim.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All tests pass already."}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Now wiring up the handler."}]}}
JSON
"$CL" --all "$D/midclaim.jsonl" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T15 --all catches a mid-session claim" || bad "T15 all exit" "rc"

rm -rf "$D"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
