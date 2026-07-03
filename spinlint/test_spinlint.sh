#!/usr/bin/env bash
# Tests for spinlint — flags WASTED-LOOP / stuck agent sessions from a transcript.
# Deterministic + offline: synthetic JSONL transcripts exercising each spin signal,
# and the load-bearing rule that a retry which eventually SUCCEEDS is never flagged.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SL="$HERE/spinlint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

D=$(mktemp -d /tmp/spinlint.XXXXXX)

# --- T1/T2: REPEAT-CALL — same Bash command 3x, every run errors -> spin, exit 1
cat > "$D/repeat.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"a1","input":{"command":"make build"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"a1","is_error":true,"content":"cc: fatal error"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"a2","input":{"command":"make build"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"a2","is_error":true,"content":"cc: fatal error"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"a3","input":{"command":"make build"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"a3","is_error":true,"content":"cc: fatal error"}]}}
JSON
"$SL" "$D/repeat.jsonl" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T1 repeated failing call => exit 1" || bad "T1 repeat exit" "rc"
o=$("$SL" "$D/repeat.jsonl" 2>&1); echo "$o" | grep -q "REPEAT-CALL" && ok "T2 reports REPEAT-CALL" || bad "T2 repeat" "$o"

# --- T3 (LOAD-BEARING): same command retried but the LAST run SUCCEEDS is NOT a spin,
#     because the (name,input) repeats but the error streak breaks -> here we vary nothing
#     yet the final result is success, so REPEAT-ERROR must not fire. Use 2 fails + 1 ok and
#     a higher --repeat so REPEAT-CALL (count<thresh) also stays quiet -> clean exit 0.
cat > "$D/recovers.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"b1","input":{"command":"flaky deploy"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"network blip"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"b2","input":{"command":"flaky deploy"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b2","is_error":false,"content":"deployed ok"}]}}
JSON
"$SL" "$D/recovers.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T3 retry that recovers is clean (exit 0)" || bad "T3 recovers exit" "rc"

# --- T4: REPEAT-ERROR — same normalized error 3x across DIFFERENT commands -> not learning
cat > "$D/repeaterr.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"c1","input":{"command":"step one"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"c1","is_error":true,"content":"ModuleNotFoundError: no module named foo"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"c2","input":{"command":"step two"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"c2","is_error":true,"content":"ModuleNotFoundError: no module named foo"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"c3","input":{"command":"step three"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"c3","is_error":true,"content":"ModuleNotFoundError: no module named foo"}]}}
JSON
o=$("$SL" "$D/repeaterr.jsonl" 2>&1); echo "$o" | grep -q "REPEAT-ERROR" && ok "T4 reports REPEAT-ERROR" || bad "T4 repeaterr" "$o"

# --- T5: PING-PONG — same file edited with oscillating changes A/B/A/B -> churn
cat > "$D/pingpong.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"e1","input":{"file_path":"/x/app.py","old_string":"A","new_string":"B"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"e2","input":{"file_path":"/x/app.py","old_string":"B","new_string":"A"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"e3","input":{"file_path":"/x/app.py","old_string":"A","new_string":"B"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"e4","input":{"file_path":"/x/app.py","old_string":"B","new_string":"A"}}]}}
JSON
o=$("$SL" "$D/pingpong.jsonl" 2>&1); echo "$o" | grep -q "PING-PONG" && ok "T5 reports PING-PONG churn" || bad "T5 pingpong" "$o"

# --- T6: a productive session (varied calls, no repeated error) -> clean exit 0
cat > "$D/clean.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"d1","input":{"command":"ls"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"d1","is_error":false,"content":"app.py"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"d2","input":{"command":"pytest"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"d2","is_error":false,"content":"2 passed"}]}}
JSON
"$SL" "$D/clean.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T6 productive session exits 0" || bad "T6 clean exit" "rc"
"$SL" "$D/clean.jsonl" 2>&1 | grep -qi "clean" && ok "T7 productive session reported clean" || bad "T7 clean msg" "$("$SL" "$D/clean.jsonl")"

# --- T8: --json includes an estimated wasted-call count
o=$("$SL" --json "$D/repeat.jsonl" 2>&1)
echo "$o" | grep -q '"estimated_wasted_calls"' && ok "T8 --json estimates wasted calls" || bad "T8 json" "$o"
echo "$o" | grep -q '"REPEAT-CALL"' && ok "T9 --json lists the detector" || bad "T9 json detector" "$o"

# --- T10: --repeat raises the REPEAT-CALL threshold so 3 repeats no longer trip default
"$SL" --repeat 5 --repeat-error 5 "$D/repeat.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T10 higher threshold => clean" || bad "T10 threshold" "rc"

# --- T11: a transcript with zero tool calls is clean (nothing to check), exit 0
cat > "$D/notool.jsonl" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"just thinking out loud"}]}}
JSON
"$SL" "$D/notool.jsonl" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T11 zero tool-calls is clean (exit 0)" || bad "T11 notool exit" "rc"

# --- T12: a file that isn't a transcript at all -> input error exit 2
printf 'just some random prose, not json\n' > "$D/notjson.txt"
"$SL" "$D/notjson.txt" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T12 non-transcript exits 2" || bad "T12 notjson exit" "rc"

# --- T13: stdin path works
"$SL" < "$D/repeat.jsonl" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T13 reads transcript from stdin" || bad "T13 stdin" "rc"

rm -rf "$D"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
