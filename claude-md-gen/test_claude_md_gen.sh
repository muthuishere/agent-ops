#!/usr/bin/env bash
# Tests for claude-md-gen — synthetic repos of various stacks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GEN="$HERE/claude-md-gen"
LINT="$HERE/../9421-context-lint/context-lint"   # pairing: generated file should lint clean
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
repo() { d=$(mktemp -d); ( cd "$d" && eval "$1" ); echo "$d"; }

# --- npm (no lockfile) -> "npm run test" ---
d=$(repo 'echo "{\"name\":\"x\",\"scripts\":{\"test\":\"jest\"}}" > package.json')
o=$("$GEN" "$d")
echo "$o" | grep -q "npm run test" && ok "T1 npm script -> npm run test" || bad "T1 npm" "$o"
echo "$o" | grep -q "## Commands" && ok "T2 has a Commands section" || bad "T2" "$o"

# --- pnpm lockfile -> pnpm ---
d=$(repo 'echo "{\"scripts\":{\"test\":\"vitest\"}}" > package.json; touch pnpm-lock.yaml')
"$GEN" "$d" | grep -q "pnpm test" && ok "T3 pnpm-lock -> pnpm test" || bad "T3 pnpm" "$("$GEN" "$d")"

# --- yarn ---
d=$(repo 'echo "{\"scripts\":{\"test\":\"mocha\"}}" > package.json; touch yarn.lock')
"$GEN" "$d" | grep -q "yarn test" && ok "T4 yarn.lock -> yarn test" || bad "T4 yarn" "$("$GEN" "$d")"

# --- python ---
d=$(repo 'touch pyproject.toml')
"$GEN" "$d" | grep -q "pytest" && ok "T5 pyproject -> pytest" || bad "T5 py" "$("$GEN" "$d")"

# --- go ---
d=$(repo 'echo "module x" > go.mod')
"$GEN" "$d" | grep -q "go test ./..." && ok "T6 go.mod -> go test" || bad "T6 go" "$("$GEN" "$d")"

# --- rust ---
d=$(repo 'echo "[package]" > Cargo.toml')
"$GEN" "$d" | grep -q "cargo test" && ok "T7 Cargo.toml -> cargo test" || bad "T7 rust" "$("$GEN" "$d")"

# --- Makefile targets ---
d=$(repo 'printf "build:\n\tgo build\ntest:\n\tgo test\n" > Makefile')
"$GEN" "$d" | grep -q "make test" && ok "T8 Makefile test target -> make test" || bad "T8 make" "$("$GEN" "$d")"

# --- no signals -> placeholder, not a fabricated command ---
d=$(repo 'echo hi > README.md')
"$GEN" "$d" | grep -q "add the commands here" && ok "T9 no signals -> honest placeholder (no fabrication)" || bad "T9 empty" "$("$GEN" "$d")"

# --- -o writes the file; refuses to overwrite ---
d=$(repo 'echo "{\"scripts\":{\"test\":\"jest\"}}" > package.json')
"$GEN" "$d" -o 2>/dev/null; [ -f "$d/CLAUDE.md" ] && ok "T10 -o writes CLAUDE.md" || bad "T10 write" "no file"
"$GEN" "$d" -o >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T11 refuses to overwrite an existing CLAUDE.md" || bad "T11 overwrite" "rc"

# --- pairing: a generated CLAUDE.md passes context-lint ---
if [ -x "$LINT" ]; then
  d=$(repo 'echo "{\"name\":\"svc\",\"scripts\":{\"build\":\"tsc\",\"test\":\"vitest\"}}" > package.json; mkdir src')
  "$GEN" "$d" -o 2>/dev/null
  ( cd "$d" && "$LINT" CLAUDE.md >/dev/null 2>&1 ); [ "$?" -eq 0 ] && ok "T12 generated CLAUDE.md passes context-lint" || bad "T12 lint" "$(cd "$d" && "$LINT" CLAUDE.md)"
else
  ok "T12 (skipped — context-lint not present)"
fi

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
