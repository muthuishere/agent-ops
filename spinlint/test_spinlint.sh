#!/usr/bin/env bash
# Tests for spinlint — flags wasted-loop / stuck agent sessions from a transcript.
# Deterministic: builds tiny JSONL transcripts inline, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SP="$HERE/spinlint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/sp.XXXXXX; }

# A dirty transcript: the SAME Bash command made 5x, every one erroring (classic
# "retrying a failing command without changing it" loop).
dirty() {
  local f=$1; : > "$f"
  for i in 1 2 3 4 5; do
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t%s","name":"Bash","input":{"command":"pytest tests/"}}]}}\n' "$i" >> "$f"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t%s","is_error":true,"content":"FAILED 3 tests"}]}}\n' "$i" >> "$f"
  done
}

# --- T1: a stuck/repeating session => REPEAT-CALL, exit 1
f=$(tmp); dirty "$f"
o=$("$SP" --transcript "$f" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "REPEAT-CALL"; } && ok "T1 repeated failing call flagged" || bad "T1" "$o (rc=$rc)"

# --- T2: it reports a wasted-call estimate
echo "$o" | grep -qi "wasted" && ok "T2 reports wasted-call estimate" || bad "T2" "$o"

# --- T3: a productive session (varied calls, all succeed) => clean, exit 0
c=$(tmp)
printf '%s\n' \
'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"x.py"}}]}}' \
'{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"a","content":"ok"}]}}' \
'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b","name":"Bash","input":{"command":"ls"}}]}}' \
'{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b","content":"files"}]}}' > "$c"
o=$("$SP" --transcript "$c" 2>&1); rc=$?
{ [ $rc -eq 0 ] && echo "$o" | grep -qi "clean"; } && ok "T3 productive session passes" || bad "T3" "$o (rc=$rc)"

# --- T4: a retry that EVENTUALLY succeeds is not a spin (outcome, not call count)
s=$(tmp)
printf '%s\n' \
'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"r1","name":"Bash","input":{"command":"make"}}]}}' \
'{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r1","is_error":true,"content":"err"}]}}' \
'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"r2","name":"Bash","input":{"command":"make"}}]}}' \
'{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r2","content":"built ok"}]}}' > "$s"
o=$("$SP" --transcript "$s" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T4 eventual success not flagged" || bad "T4" "$o (rc=$rc)"

rm -f "$f" "$c" "$s"
echo "----"; echo "spinlint: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
