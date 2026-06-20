#!/usr/bin/env bash
# Tests for agentdrift — detects drift/duplication across a repo's agent-instruction files.
# Deterministic: builds synthetic repo dirs with instruction files and asserts on the verdict.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AD="$HERE/agentdrift"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
mkrepo() { mktemp -d; }

BODY="# Project rules

Use Go for the backend and React for the frontend. Run tests with 'task test'.
Never commit secrets. Prefer small PRs. Follow the existing code style closely.
Use conventional commits. Migrations live in db/migrations and run on deploy."

# --- T1: a single instruction file => single source of truth, clean, exit 0
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "single source|one instruction|no drift|clean" && ok "T1 single file = clean" || bad "T1" "$o"
"$AD" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T1b single file exit 0" || bad "T1b exit" "rc=$?"

# --- T2: two SUBSTANTIVE files that have DIVERGED => DRIFT flagged, exit 1
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"
printf '# Project rules\n\nUse Python for the backend. Run tests with pytest. Commit straight to main.\nLarge PRs are fine. Ignore the old style guide.' > "$d/AGENTS.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "drift|diverg" && ok "T2 divergent files = DRIFT" || bad "T2" "$o"
"$AD" "$d" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T2b drift exits 1" || bad "T2b exit" "rc=$?"

# --- T3: two IDENTICAL substantive files => duplication flagged (drift risk)
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"; printf '%s' "$BODY" > "$d/AGENTS.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "duplicat|identical|copy" && ok "T3 identical files = duplication" || bad "T3" "$o"

# --- T4: canonical + redirect stub => GOOD pattern, clean, exit 0
d=$(mkrepo); printf '%s' "$BODY" > "$d/AGENTS.md"
printf 'See [AGENTS.md](./AGENTS.md) for all project rules.\n' > "$d/CLAUDE.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "redirect|canonical|points to|stub" && ok "T4 canonical+redirect recognized" || bad "T4" "$o"
"$AD" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T4b redirect pattern exit 0" || bad "T4b exit" "rc=$?"

# --- T5: lists the instruction files it found
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"; printf '%s' "$BODY" > "$d/AGENTS.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eq "CLAUDE.md" && echo "$o" | grep -Eq "AGENTS.md" && ok "T5 lists the files found" || bad "T5" "$o"

# --- T6: reports a similarity figure between the substantive files
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"
printf '# Project rules\n\nUse Python for the backend. Different content entirely here.' > "$d/AGENTS.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eq "%|similar" && ok "T6 reports similarity %" || bad "T6" "$o"

# --- T7: detects nested files (.github/copilot-instructions.md, .cursorrules)
d=$(mkrepo); mkdir -p "$d/.github"
printf '%s' "$BODY" > "$d/.github/copilot-instructions.md"
printf '%s' "$BODY" > "$d/.cursorrules"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eq "copilot-instructions" && echo "$o" | grep -Eq "cursorrules" && ok "T7 finds nested + dotfile instruction files" || bad "T7" "$o"

# --- T8: --json has documented fields
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"
printf '# rules\nUse Python. Totally different.' > "$d/AGENTS.md"
o=$("$AD" "$d" --json 2>&1)
echo "$o" | grep -Eq '"files"' && echo "$o" | grep -Eq '"verdict"|"max_pairwise_similarity"|"pairs"' && ok "T8 --json fields present" || bad "T8" "$o"

# --- T9: no instruction files => friendly, exit 0
d=$(mkrepo); printf 'hello' > "$d/README.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "no .*instruction|none found|nothing" && ok "T9 no files = friendly" || bad "T9" "$o"
"$AD" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T9b no files exit 0" || bad "T9b exit" "rc=$?"

# --- T10: recommends the canonical + redirect fix when drift/duplication found
d=$(mkrepo); printf '%s' "$BODY" > "$d/CLAUDE.md"; printf '%s' "$BODY" > "$d/AGENTS.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "canonical|redirect|single source|one file" && ok "T10 recommends the fix" || bad "T10" "$o"

# --- T11: three files, one canonical + two divergent => drift, names the offenders
d=$(mkrepo); printf '%s' "$BODY" > "$d/AGENTS.md"
printf '# rules\nUse Rust. Different.' > "$d/CLAUDE.md"
printf '# rules\nUse Java. Also different.' > "$d/.cursorrules"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "drift|diverg" && ok "T11 three-file drift detected" || bad "T11" "$o"

# --- T12: a SYMLINK CLAUDE.md -> AGENTS.md is a redirect (good), NOT duplication
d=$(mkrepo); printf '%s' "$BODY" > "$d/AGENTS.md"; ln -s AGENTS.md "$d/CLAUDE.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "redirect|canonical|symlink" && ok "T12 symlink = redirect, not duplication" || bad "T12" "$o"
echo "$o" | grep -Eiq "duplicat" && bad "T12b symlink wrongly called duplication" "$o" || ok "T12b symlink not flagged as duplication"
"$AD" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T12c symlink-redirect exit 0" || bad "T12c exit" "rc=$?"

# --- T13: a 10-byte '@AGENTS.md' import stub is a redirect (Claude Code import syntax)
d=$(mkrepo); printf '%s' "$BODY" > "$d/AGENTS.md"; printf '@AGENTS.md\n' > "$d/CLAUDE.md"
o=$("$AD" "$d" 2>&1)
echo "$o" | grep -Eiq "redirect|canonical" && ok "T13 @import stub = redirect" || bad "T13" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
