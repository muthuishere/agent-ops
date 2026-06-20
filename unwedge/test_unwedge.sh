#!/usr/bin/env bash
# Tests for `unwedge`. Each test writes a synthetic JSONL transcript that mimics
# the real Claude Code schema (lines: mode / snapshot / assistant / user, where
# assistant/user carry message.content block lists).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UW="$HERE/unwedge"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/unwedge-test.XXXXXX; }

# --- building blocks (one JSON object per line) ---
l_mode()     { echo '{"type":"mode","sessionId":"s","mode":"default"}'; }
l_snap()     { echo '{"type":"file-history-snapshot","sessionId":"s","messageId":"m","snapshot":{}}'; }
l_user_txt() { echo '{"type":"user","sessionId":"s","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}'; }
# a user line carrying a tool_result — the clean boundary we want to land on
l_user_tr()  { echo '{"type":"user","sessionId":"s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}'; }
# a healthy assistant turn: thinking THEN text (ends clean)
l_asst_ok()  { echo '{"type":"assistant","sessionId":"s","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm","signature":"sig"},{"type":"text","text":"done"}]}}'; }
# a healthy assistant turn ending in tool_use (waiting for a tool_result — NOT the wedge)
l_asst_tool(){ echo '{"type":"assistant","sessionId":"s","message":{"role":"assistant","content":[{"type":"text","text":"running"},{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}'; }
# the WEDGE: assistant turn that is ONLY an orphaned signed thinking block with empty text (issue #63147)
l_asst_orphan(){ echo '{"type":"assistant","sessionId":"s","message":{"role":"assistant","content":[{"type":"thinking","thinking":"","signature":"sig123"}]}}'; }

# --- Test 1: orphaned trailing thinking turn IS detected as wedged ---
f=$(tmp); { l_mode; l_user_txt; l_asst_ok; l_user_tr; l_asst_orphan; } > "$f"
"$UW" diagnose "$f" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "T1 diagnose flags wedged (exit 1)" || bad "T1 diagnose should exit 1 (got $rc)"

# --- Test 2: fix --write trims to the last clean user(tool_result) line, leaves it valid ---
"$UW" fix "$f" --write >/dev/null 2>&1
last=$(tail -1 "$f")
echo "$last" | grep -q '"tool_result"' && ok "T2 fix lands on the clean user tool_result line" || bad "T2 last line not the user tool_result: $last"
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$last" 2>/dev/null && ok "T2 last line is valid JSON" || bad "T2 last line not valid JSON"
# after fix the file must be CLEAN (idempotent: no longer wedged)
"$UW" diagnose "$f" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T2 repaired file is now clean" || bad "T2 still wedged after fix"

# --- Test 3: a backup was written ---
ls "$f".unwedge-bak-* >/dev/null 2>&1 && ok "T3 backup created" || bad "T3 no backup file"

# --- Test 4: a HEALTHY transcript (ends in assistant text) is CLEAN + fix refuses ---
g=$(tmp); { l_mode; l_user_txt; l_asst_ok; } > "$g"
"$UW" diagnose "$g" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T4 healthy transcript diagnosed clean" || bad "T4 healthy flagged wedged"
"$UW" fix "$g" --write >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T4 fix refuses a clean transcript" || bad "T4 fix should refuse clean"
[ "$(wc -l < "$g")" -eq 3 ] && ok "T4 clean transcript untouched" || bad "T4 clean transcript was modified"

# --- Test 5: assistant ending in tool_use (mid-tool, not thinking) is NOT wedged ---
h=$(tmp); { l_mode; l_user_txt; l_asst_tool; } > "$h"
"$UW" diagnose "$h" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T5 trailing tool_use is not the wedge" || bad "T5 misflagged tool_use as wedged"

# --- Test 6: orphan followed by trailing non-message lines (snapshot) still detected + trimmed ---
k=$(tmp); { l_mode; l_user_txt; l_asst_ok; l_user_tr; l_asst_orphan; l_snap; } > "$k"
"$UW" diagnose "$k" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T6 wedge detected past a trailing snapshot line" || bad "T6 missed wedge behind snapshot"
"$UW" fix "$k" --write >/dev/null 2>&1
tail -1 "$k" | grep -q '"tool_result"' && ok "T6 fix trims orphan + trailing snapshot to the user line" || bad "T6 did not trim to user line"

# --- Test 7: dry-run does NOT modify the file ---
m=$(tmp); { l_mode; l_user_txt; l_asst_ok; l_user_tr; l_asst_orphan; } > "$m"
before=$(wc -l < "$m"); "$UW" fix "$m" >/dev/null 2>&1; after=$(wc -l < "$m")
[ "$before" -eq "$after" ] && ok "T7 dry-run leaves the file unchanged" || bad "T7 dry-run modified the file"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
