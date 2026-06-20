#!/usr/bin/env bash
# Tests for agent-waste — audits a Claude Code session transcript for wasted work.
# Deterministic: builds synthetic .jsonl transcripts and asserts on the report.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AW="$HERE/agent-waste"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

# build a synthetic transcript via the python helper (keeps the fixtures honest to the real shape)
mk() {  # mk <out> <spec.py-printed-lines>
  python3 "$HERE/mk_fixture.py" "$1"
}

# --- T1: a file read 3 times => 2 redundant reads flagged
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" reread > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eiq "duplicate read|read .*3|re-?read" && ok "T1 flags duplicate reads" || bad "T1" "$o"

# --- T2: reading a file the agent just edited => read-after-edit anti-pattern
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" read_after_edit > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eiq "after .*edit|just edited|own edit" && ok "T2 flags read-after-own-edit" || bad "T2" "$o"

# --- T3: identical Bash command repeated => repeated-command finding
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" dup_bash > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eiq "repeat|identical|ran .*time|duplicate command" && ok "T3 flags repeated bash" || bad "T3" "$o"

# --- T4: estimates wasted tokens (a number), labeled as an estimate
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" reread > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eoq "[0-9]+" && echo "$o" | grep -Eiq "estimat|approx|~|≈" && ok "T4 estimates wasted tokens (labeled)" || bad "T4" "$o"

# --- T5: a clean transcript (each file read once, no repeats) => no waste, exit 0
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" clean > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eiq "no .*waste|clean|nothing" && ok "T5 clean transcript reports no waste" || bad "T5" "$o"
"$AW" "$F" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T5b clean exits 0" || bad "T5b exit" "rc=$?"

# --- T6: --json emits machine-readable totals
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" reread > "$F"
o=$("$AW" "$F" --json 2>&1)
echo "$o" | grep -Eq '"wasted_est_tokens"|"findings"' && ok "T6 --json has totals" || bad "T6" "$o"

# --- T7: --threshold-tokens gate exits 1 when wasted exceeds it
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" reread > "$F"
"$AW" "$F" --threshold-tokens 1 >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T7 over-threshold exits 1" || bad "T7 exit" "rc=$?"
"$AW" "$F" --threshold-tokens 100000000 >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T7b under-threshold exits 0" || bad "T7b exit" "rc=$?"

# --- T8: repeated grep/glob search flagged
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" dup_search > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eiq "search|grep|glob" && ok "T8 flags repeated search" || bad "T8" "$o"

# --- T9: a nonexistent file => error, nonzero exit
"$AW" /no/such/transcript.jsonl >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T9 missing file nonzero exit" || bad "T9" "rc"

# --- T10: malformed JSON lines are skipped, not fatal (real transcripts have noise)
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" reread > "$F"
printf '\n{ this is not json\n' >> "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eiq "duplicate read|re-?read" && ok "T10 tolerates malformed lines" || bad "T10" "$o"

# --- T11: the heaviest single waste (top offender) is named
F=$(mktemp /tmp/aw.XXXXXX)
python3 "$HERE/mk_fixture.py" reread > "$F"
o=$("$AW" "$F" 2>&1)
echo "$o" | grep -Eq "/big\.txt|big\.txt" && ok "T11 names the worst offender file" || bad "T11" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
