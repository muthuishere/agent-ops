#!/usr/bin/env bash
# Tests for context-carry — weights each tool result by how long it stays in context.
# The core claim: an identical big read costs far more EARLY in a session than LATE,
# because the agent loop re-sends it on every later turn.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="$HERE/context-carry"
MK="$HERE/mk_fixture.py"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
mkf() { f=$(mktemp /tmp/cc.XXXXXX); python3 "$MK" "$1" > "$f"; echo "$f"; }

# --- T1: the SAME big read carries far more early than late (the whole thesis)
EARLY=$(mkf early_big); LATE=$(mkf late_big)
ce=$("$CC" "$EARLY" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["total_carry_token_turns"])')
cl=$("$CC" "$LATE"  --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["total_carry_token_turns"])')
python3 -c "import sys; sys.exit(0 if $ce > $cl*3 else 1)" && ok "T1 early big read carries >3x a late one ($ce vs $cl)" || bad "T1" "early=$ce late=$cl"

# --- T2: naive token SUM is identical for early vs late (proving carry != sum)
ne=$("$CC" "$EARLY" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["total_result_tokens"])')
nl=$("$CC" "$LATE"  --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["total_result_tokens"])')
[ "$ne" = "$nl" ] && ok "T2 raw token sum is identical ($ne) — carry is the differentiator" || bad "T2" "ne=$ne nl=$nl"

# --- T3: the heaviest-carry item is named in human output
f=$(mkf mixed)
o=$("$CC" "$f" 2>&1)
echo "$o" | grep -Eq "early\.py" && ok "T3 names the early file as top carrier" || bad "T3" "$o"
echo "$o" | grep -Eiq "token-turns|carry" && ok "T3b uses the carry/token-turns framing" || bad "T3b" "$o"

# --- T4: a single-turn transcript has zero carry (nothing re-sent after it)
f=$(mkf single)
z=$("$CC" "$f" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["total_carry_token_turns"])')
[ "$z" = "0" ] && ok "T4 single-turn carry is 0" || bad "T4" "got $z"

# --- T5: reports a turn count
f=$(mkf early_big)
o=$("$CC" "$f" 2>&1)
echo "$o" | grep -Eiq "10 turn|turns" && ok "T5 reports turn count" || bad "T5" "$o"

# --- T6: caching-aware dollar view is present and labeled an estimate
f=$(mkf early_big)
o=$("$CC" "$f" 2>&1)
echo "$o" | grep -Eiq "cache|estimat|~|≈" && ok "T6 honest about caching/estimate" || bad "T6" "$o"

# --- T7: --json has the documented fields
f=$(mkf early_big)
o=$("$CC" "$f" --json 2>&1)
echo "$o" | grep -Eq '"total_carry_token_turns"' && echo "$o" | grep -Eq '"turns"' && ok "T7 --json fields present" || bad "T7" "$o"

# --- T8: malformed lines tolerated
f=$(mkf early_big); printf '\nnot json here\n' >> "$f"
"$CC" "$f" >/dev/null 2>&1 && ok "T8 tolerates malformed lines (exit 0)" || bad "T8" "rc=$?"

# --- T9: missing file => nonzero exit
"$CC" /no/such.jsonl >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T9 missing file nonzero exit" || bad "T9" "rc"

# --- T10: top-carrier in mixed is the EARLY file, not the equal-sized LATE one
f=$(mkf mixed)
top=$("$CC" "$f" --json | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["top"][0]["label"])')
echo "$top" | grep -q "early.py" && ok "T10 top carrier is the early read (not the equal late one)" || bad "T10" "top=$top"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
