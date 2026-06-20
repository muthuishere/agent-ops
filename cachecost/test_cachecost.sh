#!/usr/bin/env bash
# Tests for cachecost — pure cost arithmetic on synthetic Claude `usage` objects.
# No API calls: the math is deterministic and that's what we lock down.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="$HERE/cachecost"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/cachecost.XXXXXX; }

w=$(tmp); echo '{"input_tokens":30,"cache_creation_input_tokens":5000,"cache_read_input_tokens":0,"output_tokens":5}' > "$w"
r=$(tmp); echo '{"input_tokens":30,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":5}' > "$r"
n=$(tmp); echo '{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}' > "$n"

# --- Test 1: a cache READ is ~90% off the input ---
out=$("$CC" explain "$r")
echo "$out" | grep -q "READ (served from cache" && ok "T1 read state detected" || bad "T1 read state" "$out"
echo "$out" | grep -q "89.5% off" && ok "T1 read is 89.5% off" || bad "T1 savings pct" "$out"

# --- Test 2: a cache WRITE costs MORE than uncached (the 1.25x premium) ---
out=$("$CC" explain "$w")
echo "$out" | grep -q "WRITE (first hit" && ok "T2 write state detected" || bad "T2 write state" "$out"
# eq cost 6,280 > uncached 5,030
echo "$out" | grep -q "6,280" && ok "T2 write eq-cost 6,280" || bad "T2 write eq-cost" "$out"
echo "$out" | grep -q "5,030" && ok "T2 uncached baseline 5,030" || bad "T2 baseline" "$out"

# --- Test 3: no cache fields => 0% savings, NO CACHE state ---
out=$("$CC" explain "$n")
echo "$out" | grep -q "NO CACHE" && ok "T3 no-cache detected" || bad "T3 no-cache" "$out"

# --- Test 4: amortize 1 write + 9 reads of a 5000-tok prefix => 78.5% cheaper ---
out=$("$CC" amortize "$w" "$r" --reads 10)
echo "$out" | grep -q "78.5% cheaper" && ok "T4 amortized 10 reqs = 78.5% cheaper" || bad "T4 amortize" "$out"
echo "$out" | grep -q "10,750" && ok "T4 cached total 10,750 eq-tok" || bad "T4 cached total" "$out"
echo "$out" | grep -q "50,000" && ok "T4 uncached total 50,000 eq-tok" || bad "T4 uncached total" "$out"

# --- Test 5: 1-hour TTL multiplier (2.0x write) changes the write premium ---
out=$("$CC" explain "$w" --write-mult 2.0)
# eq = 30 + 5000*2.0 = 10,030
echo "$out" | grep -q "10,030" && ok "T5 1h-TTL write eq-cost 10,030" || bad "T5 1h write" "$out"

# --- Test 6: accepts a full message object (with nested .usage) ---
m=$(tmp); echo '{"id":"msg_x","usage":{"input_tokens":30,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":5}}' > "$m"
out=$("$CC" explain "$m")
echo "$out" | grep -q "89.5% off" && ok "T6 unwraps nested .usage" || bad "T6 nested usage" "$out"

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
