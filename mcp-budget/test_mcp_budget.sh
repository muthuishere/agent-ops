#!/usr/bin/env bash
# Tests for mcp-budget — measures the context-window cost of MCP tool definitions.
# Deterministic: drives the OFFLINE path (--tools <captured tools/list>) against real
# fixtures captured from live servers, so no network/npx is needed to run the suite.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MB="$HERE/mcp-budget"
FX="$HERE/fixtures"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

# --- T1: a single verbose tool (sequentialthinking) costs ~1000 tokens — count != cost
o=$("$MB" --tools "$FX/fixture-sequentialthinking.json" 2>&1)
echo "$o" | grep -Eq "1 tool" && ok "T1 reports 1 tool" || bad "T1" "$o"
echo "$o" | grep -Eoq "[0-9]{3,}" && ok "T1b reports a token count (3+ digits)" || bad "T1b" "$o"

# --- T2: a big multi-tool server (github, 26 tools) totals thousands of tokens
o=$("$MB" --tools "$FX/fixture-github.json" 2>&1)
echo "$o" | grep -Eq "26 tool" && ok "T2 counts all 26 github tools" || bad "T2" "$o"

# --- T3: aggregates multiple servers into a grand total, before-your-first-prompt framing
o=$("$MB" --tools "$FX/fixture-github.json" --tools "$FX/fixture-filesystem.json" 2>&1)
echo "$o" | grep -Eiq "total|before .* prompt" && ok "T3 reports an aggregate total" || bad "T3" "$o"

# --- T4: --budget gate — under the cap exits 1, generous cap exits 0
"$MB" --tools "$FX/fixture-github.json" --budget 100 >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "T4 over-budget exits 1" || bad "T4 over-budget exit" "rc=$?"
"$MB" --tools "$FX/fixture-github.json" --budget 100000 >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "T4b under-budget exits 0" || bad "T4b under-budget exit" "rc=$?"

# --- T5: % of a context window is reported (default 200k, overridable)
o=$("$MB" --tools "$FX/fixture-github.json" --window 200000 2>&1)
echo "$o" | grep -Eq "%" && ok "T5 reports a percent-of-window" || bad "T5" "$o"

# --- T6: the single largest tool is called out (the cost is description-driven)
o=$("$MB" --tools "$FX/fixture-filesystem.json" 2>&1)
echo "$o" | grep -Eiq "largest|biggest|top tool|heaviest" && ok "T6 calls out the largest tool" || bad "T6" "$o"

# --- T7: names the injection-surface point (this text is also un-authored instructions)
o=$("$MB" --tools "$FX/fixture-github.json" 2>&1)
echo "$o" | grep -Eiq "inject|instruction|didn't write|un-?authored" && ok "T7 names the injection surface" || bad "T7" "$o"

# --- T8: token count is an honest ESTIMATE, labeled as such
o=$("$MB" --tools "$FX/fixture-git.json" 2>&1)
echo "$o" | grep -Eiq "estimat|approx|~|≈" && ok "T8 labels the count an estimate" || bad "T8" "$o"

# --- T9: invalid JSON fixture => error, nonzero exit
f=$(mktemp /tmp/mb.XXXXXX); printf '%s' '{not json' > "$f"
"$MB" --tools "$f" >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T9 invalid JSON nonzero exit" || bad "T9" "rc"

# --- T10: no .mcp.json and no --tools => friendly, exit 0
d=$(mktemp -d); ( cd "$d" && "$MB" >/dev/null 2>&1 ); [ "$?" -eq 0 ] && ok "T10 nothing to measure = exit 0" || bad "T10 exit" "rc"

# --- T11: a tools/list wrapped as {"tools":[...]} is accepted (raw RPC result shape)
f=$(mktemp /tmp/mb.XXXXXX)
printf '%s' '{"tools":[{"name":"x","description":"hello world","inputSchema":{"type":"object","properties":{}}}]}' > "$f"
o=$("$MB" --tools "$f" 2>&1); echo "$o" | grep -Eq "1 tool" && ok "T11 accepts {tools:[...]} wrapper" || bad "T11" "$o"

# --- T12: --json emits machine-readable output with a total
o=$("$MB" --tools "$FX/fixture-git.json" --json 2>&1)
echo "$o" | grep -Eq '"total_est_tokens"|"est_tokens"' && ok "T12 --json has token totals" || bad "T12" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
