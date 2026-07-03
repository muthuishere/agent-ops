#!/usr/bin/env bash
# Tests for agentconfig-doctor — runs the real sibling config-audit tools present in
# this agent-ops checkout (perm-audit, mcp-audit, skill-lint, context-lint,
# trifecta-scan) against synthetic target repos. Deterministic and offline.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DOC="$HERE/agentconfig-doctor"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
newrepo() { d=$(mktemp -d /tmp/doc.XXXXXX); echo "$d"; }
run() { "$DOC" "$1" 2>&1; }

# --- T1: a dangerous settings.json => perm-audit fails, doctor exits 1
d=$(newrepo); mkdir -p "$d/.claude"
printf '%s' '{"defaultMode":"bypassPermissions","permissions":{"allow":["Bash(*)"]}}' > "$d/.claude/settings.json"
o=$(run "$d")
echo "$o" | grep -q "perm-audit" && echo "$o" | grep -qiE "perm-audit.*finding|✗" && ok "T1 perm-audit flagged" || bad "T1" "$o"
echo "$o" | grep -q "with issues" && ok "T1b summary shows issues" || bad "T1b" "$o"
"$DOC" "$d" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T2 exit 1 when a check fails" || bad "T2 exit" "rc"

# --- T3: a clean scoped settings.json (no Bash => no lethal-trifecta leg) => all clean, exit 0
d=$(newrepo); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Read(./src/**)"],"deny":["Read(./.env)","Read(~/.ssh/**)"]}}' > "$d/.claude/settings.json"
o=$(run "$d")
echo "$o" | grep -q "perm-audit" && echo "$o" | grep -q "clean" && ok "T3 perm-audit clean" || bad "T3" "$o"
echo "$o" | grep -q "with issues" && bad "T3b should have no issues" "$o" || ok "T3b no issues on clean repo"
"$DOC" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T4 exit 0 when all clean" || bad "T4 exit" "rc"

# --- T5: empty repo => file-target checks are n/a; repo-level checks still run; exit 0
d=$(newrepo)
o=$(run "$d")
echo "$o" | grep -q "n/a (no target)" && ok "T5 absent targets shown n/a" || bad "T5" "$o"
echo "$o" | grep -qE "^  ran [0-9]" && ok "T5b summary line present" || bad "T5b" "$o"
"$DOC" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T6 empty repo exits 0" || bad "T6 exit" "rc"

# --- T7: --list shows a present sibling and an absent one. agent-ops now bundles
# every tool agentconfig-doctor checks for, so there's no naturally-absent sibling
# left in a real checkout — build a controlled PARTIAL checkout instead (copy the
# doctor + only some siblings into a temp dir) to exercise the present/absent split.
o=$("$DOC" --list 2>&1)
echo "$o" | grep -q "perm-audit" && echo "$o" | grep -q "present" && ok "T7 --list shows present tool" || bad "T7" "$o"

partial=$(mktemp -d /tmp/doc-partial.XXXXXX)
mkdir -p "$partial/agentconfig-doctor" "$partial/perm-audit"
cp "$DOC" "$partial/agentconfig-doctor/agentconfig-doctor"
cp "$HERE/perm-audit/perm-audit" "$partial/perm-audit/perm-audit" 2>/dev/null || printf '#!/usr/bin/env python3\n' > "$partial/perm-audit/perm-audit"
chmod +x "$partial/agentconfig-doctor/agentconfig-doctor" "$partial/perm-audit/perm-audit"
o=$("$partial/agentconfig-doctor/agentconfig-doctor" --list 2>&1)
echo "$o" | grep -q "perm-audit.*present" && ok "T7b --list shows the bundled sibling as present" || bad "T7b present" "$o"
echo "$o" | grep -qE "hooklint.*not in checkout" && ok "T7c --list flags a missing sibling as not-in-checkout" || bad "T7c" "$o"
rm -rf "$partial"

# --- T8: an .mcp.json target makes mcp-audit a RAN row (not n/a)
d=$(newrepo)
printf '%s' '{"mcpServers":{"x":{"command":"npx","args":["-y","some-pkg"]}}}' > "$d/.mcp.json"
o=$(run "$d")
echo "$o" | grep -q "mcp-audit" && ok "T8 mcp-audit appears for present .mcp.json" || bad "T8" "$o"
# mcp-audit must NOT be marked n/a since the target exists
echo "$o" | grep -E "mcp-audit" | grep -q "n/a" && bad "T8b mcp-audit should have run" "$o" || ok "T8b mcp-audit ran (not n/a)"

# --- T9: not-a-directory arg => exit 2
"$DOC" "/tmp/nope-doctor-$$" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T9 bad dir = exit 2" || bad "T9" "rc"

# --- T10: a CLAUDE.md target makes context-lint run (context kind)
d=$(newrepo); printf '# Project\n\nDo good work.\n' > "$d/CLAUDE.md"
o=$(run "$d")
echo "$o" | grep -q "context-lint" && echo "$o" | grep -E "context-lint" | grep -qv "n/a" && ok "T10 context-lint runs for CLAUDE.md" || bad "T10" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
