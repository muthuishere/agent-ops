#!/usr/bin/env bash
# Tests for session-stats — synthetic JSONL transcripts mimicking the real schema.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SS="$HERE/session-stats"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/session-stats.XXXXXX; }

mode()   { echo '{"type":"mode","sessionId":"S1","mode":"default"}'; }
snap()   { echo '{"type":"file-history-snapshot","sessionId":"S1","snapshot":{}}'; }
utxt()   { echo '{"type":"user","sessionId":"S1","message":{"role":"user","content":[{"type":"text","text":"go"}]}}'; }
utr()    { echo '{"type":"user","sessionId":"S1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}'; }
a_bash() { echo '{"type":"assistant","sessionId":"S1","message":{"role":"assistant","content":[{"type":"text","text":"run"},{"type":"tool_use","id":"t","name":"Bash","input":{"command":"ls"}}]}}'; }
a_edit() { echo '{"type":"assistant","sessionId":"S1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Edit","input":{"file_path":"/x/a.py"}}]}}'; }
a_read() { echo '{"type":"assistant","sessionId":"S1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Read","input":{"file_path":"/x/b.py"}}]}}'; }
a_think_text(){ echo '{"type":"assistant","sessionId":"S1","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm","signature":"s"},{"type":"text","text":"done"}]}}'; }
a_orphan(){ echo '{"type":"assistant","sessionId":"S1","message":{"role":"assistant","content":[{"type":"thinking","thinking":"","signature":"s"}]}}'; }

# A representative session: 3 user turns, assistant turns using Bash, Edit, Read, plus a thinking+text turn.
f=$(tmp); { mode; utxt; a_bash; utr; a_edit; utr; a_read; utr; a_think_text; } > "$f"
out=$("$SS" "$f")

echo "### counts"
echo "$out" | grep -q "4 user" && echo "$out" | grep -q "4 assistant" && ok "T1 turn counts (4 user / 4 assistant)" || bad "T1 turns" "$out"
echo "$out" | grep -q "1 blocks" && ok "T2 one thinking block" || bad "T2 thinking" "$out"
echo "$out" | grep -Eq "1× Bash" && echo "$out" | grep -Eq "1× Edit" && echo "$out" | grep -Eq "1× Read" && ok "T3 tool histogram has Bash/Edit/Read" || bad "T3 tools" "$out"
echo "$out" | grep -q "3 tool calls total" && ok "T4 total tool calls = 3" || bad "T4 total" "$out"

echo "### files"
echo "$out" | grep -q "2 touched" && ok "T5 files touched = 2 (a.py + b.py)" || bad "T5 files" "$out"
echo "$out" | grep -q "/x/a.py" && echo "$out" | grep -q "/x/b.py" && ok "T6 lists both files" || bad "T6 file list" "$out"

echo "### health"
echo "$out" | grep -q "clean" && ok "T7 healthy session reported clean" || bad "T7 health" "$out"
# wedged: ends on an orphaned thinking turn
w=$(tmp); { mode; utxt; a_bash; utr; a_orphan; } > "$w"
"$SS" "$w" | grep -q "WEDGED" && ok "T8 wedged session flagged" || bad "T8 wedged" "$("$SS" "$w")"
# empty-text thinking is counted + surfaced
"$SS" "$w" | grep -q "empty-text" && ok "T9 empty-text thinking surfaced" || bad "T9 empty-text" "$("$SS" "$w")"

echo "### structure + files cap"
echo "$out" | grep -q "lines   :" && ok "T10 line-type census present" || bad "T10 census" "$out"
# many files → capped by default, full with --files
big=$(tmp); { mode; utxt
  for i in $(seq 1 12); do echo "{\"type\":\"assistant\",\"sessionId\":\"S1\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t\",\"name\":\"Read\",\"input\":{\"file_path\":\"/x/f$i.py\"}}]}}"; done
} > "$big"
"$SS" "$big" | grep -q "and 4 more" && ok "T11 default caps file list (8 + 'and 4 more')" || bad "T11 cap" "$("$SS" "$big" | grep -A20 files)"
[ "$("$SS" "$big" --files | grep -c '/x/f')" -eq 12 ] && ok "T12 --files shows all 12" || bad "T12 --files" "cap not lifted"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
