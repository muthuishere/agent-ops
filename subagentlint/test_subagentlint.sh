#!/usr/bin/env bash
# Tests for subagentlint — synthetic .claude/agents/*.md subagent definitions.
# Deterministic and offline: every case is a hand-built markdown file; we assert
# on the verdict text and the exit code (1 on HIGH, 0 otherwise).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SL="$HERE/subagentlint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
newdir() { d=$(mktemp -d /tmp/sub.XXXXXX); mkdir -p "$d/.claude/agents"; echo "$d"; }
agent() { printf '%s' "$2" > "$1/.claude/agents/$3"; }   # dir, content, filename
run() { "$SL" "$1" 2>&1; }

# a clean, well-formed subagent
CLEAN='---
name: code-reviewer
description: Use when reviewing a pull request or diff for correctness and style issues.
tools: Read, Grep, Glob
model: sonnet
---
You are a meticulous code reviewer. Inspect the diff and report concrete issues.'

# --- T1: clean subagent => healthy, exit 0
d=$(newdir); agent "$d" "$CLEAN" code-reviewer.md
o=$(run "$d"); echo "$o" | grep -q "subagents look healthy" && ok "T1 clean = healthy" || bad "T1" "$o"
"$SL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T2 clean exits 0" || bad "T2 exit" "rc"

# --- T3: missing description => HIGH + exit 1
d=$(newdir); agent "$d" '---
name: helper
tools: Read
---
Body here.' helper.md
o=$(run "$d"); echo "$o" | grep -q "missing 'description'" && ok "T3 missing description = HIGH" || bad "T3" "$o"
"$SL" "$d" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T4 exit 1 on HIGH" || bad "T4 exit" "rc"

# --- T5: missing name => HIGH
d=$(newdir); agent "$d" '---
description: Use when you need to do a thing that is well described in detail here.
---
Body.' noname.md
o=$(run "$d"); echo "$o" | grep -q "missing 'name'" && ok "T5 missing name = HIGH" || bad "T5" "$o"

# --- T6: no frontmatter => HIGH
d=$(newdir); agent "$d" 'just a plain markdown file with no header at all' plain.md
o=$(run "$d"); echo "$o" | grep -q "no valid frontmatter" && ok "T6 no frontmatter = HIGH" || bad "T6" "$o"

# --- T7: duplicate name across two files => HIGH
d=$(newdir); agent "$d" "$CLEAN" code-reviewer.md
agent "$d" '---
name: code-reviewer
description: Use when you want a second reviewer with a different lens on the diff.
tools: Read
---
Another reviewer.' reviewer2.md
o=$(run "$d"); echo "$o" | grep -q "duplicate name 'code-reviewer'" && ok "T7 duplicate name = HIGH" || bad "T7" "$o"

# --- T8: no tools => WARN (inherits all)
d=$(newdir); agent "$d" '---
name: planner
description: Use when planning a multi-step implementation before writing any code.
---
Plan carefully.' planner.md
o=$(run "$d"); echo "$o" | grep -q "inherits ALL tools" && ok "T8 no tools = WARN" || bad "T8" "$o"
"$SL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T9 WARN-only exits 0" || bad "T9 exit" "rc"

# --- T10: mis-cased tool name => WARN with suggestion
d=$(newdir); agent "$d" '---
name: searcher
description: Use when searching the codebase for symbols, files, or naming conventions.
tools: read, grep
---
Search.' searcher.md
o=$(run "$d"); echo "$o" | grep -q "mis-cased — did you mean 'Read'" && ok "T10 mis-cased tool = WARN" || bad "T10" "$o"

# --- T11: unknown tool name => WARN
d=$(newdir); agent "$d" '---
name: builder
description: Use when building and compiling the project from a clean checkout state.
tools: Read, Compile
---
Build.' builder.md
o=$(run "$d"); echo "$o" | grep -q "tool 'Compile' is not a known built-in" && ok "T11 unknown tool = WARN" || bad "T11" "$o"

# --- T12: MCP tool name is accepted (no warning)
d=$(newdir); agent "$d" '---
name: kite-trader
description: Use when placing or inspecting orders on the kite trading venue for the desk.
tools: Read, mcp__kite__get_positions
---
Trade.' kite.md
o=$(run "$d"); echo "$o" | grep -qE "mcp__kite|not a known" && bad "T12 mcp__ should be accepted" "$o" || ok "T12 mcp__ tool accepted"

# --- T13: powerful tools on a read-only-sounding agent => WARN
d=$(newdir); agent "$d" '---
name: auditor
description: Use this read-only agent to audit and review configuration for risks.
tools: Read, Bash, Write
---
Audit.' auditor.md
o=$(run "$d"); echo "$o" | grep -q "grants Bash, Write but reads as read-only" && ok "T13 over-permissioned read-only = WARN" || bad "T13" "$o"

# --- T14: short description => WARN
d=$(newdir); agent "$d" '---
name: tiny
description: Does stuff.
tools: Read
---
Body.' tiny.md
o=$(run "$d"); echo "$o" | grep -q "description is very short" && ok "T14 short description = WARN" || bad "T14" "$o"

# --- T15: description with no trigger cue => WARN
d=$(newdir); agent "$d" '---
name: formatter
description: A general agent that reformats source files and tidies whitespace nicely.
tools: Edit
---
Format.' formatter.md
o=$(run "$d"); echo "$o" | grep -q "no 'use when" && ok "T15 no trigger cue = WARN" || bad "T15" "$o"

# --- T16: bad name casing => WARN
d=$(newdir); agent "$d" '---
name: Code_Reviewer
description: Use when reviewing a pull request or diff for correctness and style problems.
tools: Read
---
Review.' weird.md
o=$(run "$d"); echo "$o" | grep -q "isn.t lowercase-kebab" && ok "T16 bad name casing = WARN" || bad "T16" "$o"

# --- T17: empty body => WARN
d=$(newdir); printf '%s' '---
name: empty-agent
description: Use when you want an agent that currently has no system prompt body yet.
tools: Read
---
' > "$d/.claude/agents/empty.md"
o=$(run "$d"); echo "$o" | grep -q "empty body" && ok "T17 empty body = WARN" || bad "T17" "$o"

# --- T18: unrecognised model => WARN
d=$(newdir); agent "$d" '---
name: gpt-agent
description: Use when you specifically want to route this work to a non-claude model.
tools: Read
model: gpt-4o
---
Body.' gpt.md
o=$(run "$d"); echo "$o" | grep -q "model 'gpt-4o' is unrecognised" && ok "T18 bad model = WARN" || bad "T18" "$o"

# --- T19: no agents dir at all => friendly, exit 0
d=$(mktemp -d /tmp/sub.XXXXXX)
"$SL" "$d/.claude/agents" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T19 missing agents dir = exit 0" || bad "T19" "rc"

# --- T20: lint a single file directly
d=$(newdir); agent "$d" "$CLEAN" code-reviewer.md
o=$("$SL" "$d/.claude/agents/code-reviewer.md" 2>&1); echo "$o" | grep -q "subagents look healthy" && ok "T20 single-file lint works" || bad "T20" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
