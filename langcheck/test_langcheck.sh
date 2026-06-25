#!/usr/bin/env bash
# Tests for langcheck — flags contamination (foreign-script intrusion, mojibake,
# runaway repetition) in LLM/agent OUTPUT text. Deterministic, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LC="$HERE/langcheck"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/lc.XXXXXX; }

# --- T1: clean English text => exit 0, reports clean
o=$(printf 'this is a perfectly ordinary sentence about shipping code.\n' | "$LC" 2>&1); rc=$?
{ [ $rc -eq 0 ] && echo "$o" | grep -qi "clean"; } && ok "T1 clean text passes" || bad "T1" "$o (rc=$rc)"

# --- T2: a CJK run inside Latin text => SCRIPT-INTRUSION, exit 1
o=$(printf 'deploy the 世界 service to production now\n' | "$LC" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "SCRIPT-INTRUSION"; } && ok "T2 CJK intrusion fails" || bad "T2" "$o (rc=$rc)"

# --- T3: a non-trivial line repeated >= threshold => REPETITION, exit 1
f=$(tmp); for i in 1 2 3 4 5; do echo "the same degenerate line over and over"; done > "$f"
o=$("$LC" "$f" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "REPETITION"; } && ok "T3 runaway repetition fails" || bad "T3" "$o (rc=$rc)"
rm -f "$f"

# --- T4: a genuinely non-Latin document is NOT flagged as intrusion (it's the norm there)
o=$(printf '世界您好这是一段完全中文的文本内容并不是混入\n' | "$LC" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T4 predominantly-non-Latin doc not flagged" || bad "T4" "$o (rc=$rc)"

# --- T5: reads from a file path as well as stdin
f=$(tmp); printf 'plain ascii line\n' > "$f"
o=$("$LC" "$f" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T5 file input clean passes" || bad "T5" "$o (rc=$rc)"
rm -f "$f"

echo "----"; echo "langcheck: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
