#!/usr/bin/env bash
# Tests for context-lint — synthetic CLAUDE.md / AGENTS.md.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CL="$HERE/context-lint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

W=$(mktemp -d); cd "$W"

# --- lean, healthy CLAUDE.md => clean, exit 0 ---
cat > CLAUDE.md <<'EOF'
# Project
Build: `npm run build`. Test: `npm test`.
- Use strict mode.
- Prefer named exports.
EOF
o=$("$CL" CLAUDE.md 2>&1); echo "$o" | grep -q "lean and current" && ok "T1 lean file is clean" || bad "T1 lean" "$o"
"$CL" CLAUDE.md >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T2 clean file exits 0" || bad "T2 exit" "rc"

# --- bloated (>250 instructions) => HIGH ---
{ echo "# Big"; echo "Test: \`npm test\`"; for i in $(seq 1 260); do echo "- Rule $i to always follow."; done; } > BIG.md
o=$("$CL" BIG.md 2>&1); echo "$o" | grep -Eq "HIGH.*instructions" && ok "T3 >250 instructions = HIGH bloat" || bad "T3 bloat" "$o"
"$CL" BIG.md >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T4 findings => exit 1" || bad "T4 exit" "rc"

# --- mid bloat (~180) => WARN not HIGH ---
{ echo "# Mid"; echo "Test: \`npm test\`"; for i in $(seq 1 180); do echo "- Rule $i."; done; } > MID.md
o=$("$CL" MID.md 2>&1); echo "$o" | grep -Eq "WARN.*instructions" && ok "T5 ~180 instructions = WARN" || bad "T5 mid" "$o"

# --- stale path reference => HIGH; a real one is NOT flagged ---
mkdir -p src; echo x > src/real.js
{ echo "# Refs"; echo "Test: \`npm test\`"; echo "See \`src/real.js\` and \`src/ghost.js\`."; } > REFS.md
o=$("$CL" REFS.md 2>&1)
echo "$o" | grep -q "ghost.js" && ok "T6 stale path flagged" || bad "T6 stale" "$o"
echo "$o" | grep -q "real.js" && bad "T7 existing path wrongly flagged" "$o" || ok "T7 existing path not flagged"

# --- missing build/test command => INFO; present => not ---
{ echo "# NoTest"; echo "- be nice."; } > NOTEST.md
o=$("$CL" NOTEST.md 2>&1); echo "$o" | grep -q "no build/test" && ok "T8 missing test command = INFO" || bad "T8 notest" "$o"

# --- AGENTS.md is auto-discovered ---
rm -f CLAUDE.md; cat > AGENTS.md <<'EOF'
# A
Test: `pytest`.
- one rule.
EOF
o=$("$CL" 2>&1); echo "$o" | grep -q "AGENTS.md" && ok "T9 auto-discovers AGENTS.md" || bad "T9 agents" "$o"

# --- no context file => friendly note, exit 0 ---
E=$(mktemp -d); ( cd "$E" && "$CL" >/dev/null 2>&1 ); [ "$?" -eq 0 ] && ok "T10 no file = exit 0" || bad "T10 nofile" "rc"

cd /; rm -rf "$W" "$E"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
