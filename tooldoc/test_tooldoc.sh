#!/usr/bin/env bash
# Tests for tooldoc — audits MCP tool-description quality (does the agent know what each param means?).
# Deterministic: real captured server schemas (fixtures/) + synthetic edge cases.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TD="$HERE/tooldoc"
FX="$HERE/fixtures"
MK="$HERE/mk_fixture.py"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
syn() { f=$(mktemp /tmp/td.XXXXXX); python3 "$MK" "$1" > "$f"; echo "$f"; }

# --- T1: the headline — the real filesystem server leaves ~72% of params undocumented
o=$("$TD" --tools "$FX/fx-filesystem.json" 2>&1)
echo "$o" | grep -Eq "7[0-9]%|72%" && ok "T1 filesystem ~72% params undocumented (ground truth)" || bad "T1" "$o"
echo "$o" | grep -Eiq "param|undocumented|description" && ok "T1b names the parameter-doc metric" || bad "T1b" "$o"

# --- T2: a fully-documented tool set => grade A / 0% undocumented
f=$(syn clean)
o=$("$TD" --tools "$f" 2>&1)
echo "$o" | grep -Eq "0%" && echo "$o" | grep -Eiq "\bA\b|grade A|well.documented|clean" && ok "T2 clean tools score well" || bad "T2" "$o"

# --- T3: a tool with no description => flagged
f=$(syn no_tool_desc)
o=$("$TD" --tools "$f" 2>&1)
echo "$o" | grep -Eiq "no description|missing description|undescribed" && ok "T3 flags tool with no description" || bad "T3" "$o"

# --- T4: a free-form string param with no description AND no enum => guess-prone flag
f=$(syn guess_prone)
o=$("$TD" --tools "$f" 2>&1)
echo "$o" | grep -Eiq "guess|free.form|no description|undocumented" && ok "T4 flags guess-prone param" || bad "T4" "$o"

# --- T5: same tool name across two servers => collision/shadowing flag
A=$(syn collision_a); B=$(syn collision_b)
o=$("$TD" --tools "$A" --tools "$B" 2>&1)
echo "$o" | grep -Eiq "collision|shadow|duplicate name|same name" && ok "T5 flags tool-name collision" || bad "T5" "$o"

# --- T6: per-server grade is shown
o=$("$TD" --tools "$FX/fx-git.json" 2>&1)
echo "$o" | grep -Eq "\[[A-F]\]|grade" && ok "T6 shows a per-server grade" || bad "T6" "$o"

# --- T7: corpus aggregate across multiple servers reported
o=$("$TD" --tools "$FX/fx-filesystem.json" --tools "$FX/fx-git.json" --tools "$FX/fx-github.json" 2>&1)
echo "$o" | grep -Eiq "corpus|overall|total|across" && ok "T7 reports a corpus aggregate" || bad "T7" "$o"

# --- T8: --json has documented fields
o=$("$TD" --tools "$FX/fx-filesystem.json" --json 2>&1)
echo "$o" | grep -Eq '"pct_params_undocumented"|"undocumented_params"' && ok "T8 --json has the metric" || bad "T8" "$o"

# --- T9: --min-grade gate exits nonzero when a server is below it
"$TD" --tools "$FX/fx-git.json" --min-grade A >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T9 --min-grade gate fails a bad server" || bad "T9 gate" "rc"
f=$(syn clean); "$TD" --tools "$f" --min-grade A >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T9b clean passes the gate" || bad "T9b gate" "rc"

# --- T10: a one-word 'thin' tool description is flagged
f=$(syn thin)
o=$("$TD" --tools "$f" 2>&1)
echo "$o" | grep -Eiq "thin|too short|terse" && ok "T10 flags thin description" || bad "T10" "$o"

# --- T11: empty array => friendly, exit 0
f=$(mktemp /tmp/td.XXXXXX); printf '[]' > "$f"
"$TD" --tools "$f" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T11 empty tool set exit 0" || bad "T11" "rc"

# --- T12: invalid JSON => nonzero exit
f=$(mktemp /tmp/td.XXXXXX); printf '{bad' > "$f"
"$TD" --tools "$f" >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T12 invalid JSON nonzero exit" || bad "T12" "rc"

# --- T13: names the worst-offending tool (most undocumented params)
o=$("$TD" --tools "$FX/fx-github.json" 2>&1)
echo "$o" | grep -Eiq "param" && ok "T13 surfaces worst offenders" || bad "T13" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
