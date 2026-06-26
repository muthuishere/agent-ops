#!/usr/bin/env bash
# Tests for commandlint — synthetic .claude/commands/*.md slash commands.
# Deterministic and offline; assert on verdict text + exit code (1 on HIGH).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CL="$HERE/commandlint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
newdir() { d=$(mktemp -d /tmp/cmd.XXXXXX); mkdir -p "$d/.claude/commands"; echo "$d"; }
cmd() { printf '%s' "$2" > "$1/.claude/commands/$3"; }   # dir, content, filename
run() { "$CL" "$1" 2>&1; }

# a clean, well-formed command
CLEAN='---
description: Summarise the current git diff in plain language.
argument-hint: [base-branch]
allowed-tools: Bash(git diff:*), Read
---
Summarise the diff for $ARGUMENTS using the output below.'

# --- T1: clean command => healthy, exit 0
d=$(newdir); cmd "$d" "$CLEAN" summarise.md
o=$(run "$d"); echo "$o" | grep -q "slash commands look healthy" && ok "T1 clean = healthy" || bad "T1" "$o"
"$CL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T2 clean exits 0" || bad "T2 exit" "rc"

# --- T3: $ARGUMENTS spliced into a !`...` bash command => HIGH injection + exit 1
d=$(newdir); cmd "$d" '---
description: Show git log for a ref.
argument-hint: [ref]
allowed-tools: Bash(git log:*)
---
Here is the log:
!`git log $ARGUMENTS`' badlog.md
o=$(run "$d"); echo "$o" | grep -q "spliced into a .* bash command" && ok "T3 bash injection = HIGH" || bad "T3" "$o"
"$CL" "$d" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T4 exit 1 on HIGH" || bad "T4 exit" "rc"

# --- T5: bash used but allowed-tools omits Bash => WARN
d=$(newdir); cmd "$d" '---
description: Show current branch status.
allowed-tools: Read
---
Current status:
!`git status`' nobash.md
o=$(run "$d"); echo "$o" | grep -q "doesn.t include Bash" && ok "T5 bash-not-allowed = WARN" || bad "T5" "$o"
"$CL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T6 WARN-only exits 0" || bad "T6 exit" "rc"

# --- T7: unrestricted Bash grant => WARN
d=$(newdir); cmd "$d" '---
description: Run anything.
allowed-tools: Bash
---
Do the thing.' openbash.md
o=$(run "$d"); echo "$o" | grep -q "grants unrestricted Bash" && ok "T7 open Bash = WARN" || bad "T7" "$o"

# --- T8: $ARGUMENTS used but no argument-hint => WARN
d=$(newdir); cmd "$d" '---
description: Greet someone by name.
---
Say hello to $ARGUMENTS warmly.' greet.md
o=$(run "$d"); echo "$o" | grep -q "no .argument-hint" && ok "T8 args-no-hint = WARN" || bad "T8" "$o"

# --- T9: argument-hint but body never uses args => WARN
d=$(newdir); cmd "$d" '---
description: Tidy whitespace in the repo.
argument-hint: [path]
---
Reformat the files and tidy trailing whitespace.' tidy.md
o=$(run "$d"); echo "$o" | grep -q "the body never uses" && ok "T9 hint-no-args = WARN" || bad "T9" "$o"

# --- T10: missing description => WARN
d=$(newdir); cmd "$d" 'Just a prompt body with no frontmatter at all.' plain.md
o=$(run "$d"); echo "$o" | grep -q "no .description" && ok "T10 no description = WARN" || bad "T10" "$o"

# --- T11: empty body => HIGH
d=$(newdir); printf '%s' '---
description: A command that forgot its prompt.
---
' > "$d/.claude/commands/empty.md"
o=$(run "$d"); echo "$o" | grep -q "empty body" && ok "T11 empty body = HIGH" || bad "T11" "$o"

# --- T12: mis-cased allowed-tools => WARN with suggestion
d=$(newdir); cmd "$d" '---
description: Read a file and explain it.
allowed-tools: read
---
Explain the code.' miscase.md
o=$(run "$d"); echo "$o" | grep -q "mis-cased — did you mean .Read." && ok "T12 mis-cased tool = WARN" || bad "T12" "$o"

# --- T13: MCP tool in allowed-tools accepted (no warning)
d=$(newdir); cmd "$d" '---
description: Fetch positions from the trading venue.
allowed-tools: mcp__kite__get_positions
---
Show my open positions.' mcp.md
o=$(run "$d"); echo "$o" | grep -qE "not a known tool|mis-cased" && bad "T13 mcp__ should be accepted" "$o" || ok "T13 mcp__ accepted"

# --- T14: bad @file reference => INFO
d=$(newdir); cmd "$d" '---
description: Review against our style guide.
---
Follow the rules in @docs/STYLE-NOPE.md when reviewing.' styleref.md
o=$(run "$d"); echo "$o" | grep -q "doesn.t resolve to a file" && ok "T14 bad @ref = INFO" || bad "T14" "$o"

# --- T15: good @file reference resolves (no INFO)
d=$(newdir); printf 'rules\n' > "$d/STYLE.md"; cmd "$d" '---
description: Review against our style guide.
---
Follow @STYLE.md when reviewing.' styleok.md
o=$(run "$d"); echo "$o" | grep -q "doesn.t resolve" && bad "T15 valid @ref should not warn" "$o" || ok "T15 valid @ref ok"

# --- T16: quoted $ARGUMENTS in bash STILL flagged (injection heuristic)
d=$(newdir); cmd "$d" '---
description: grep the tree.
argument-hint: [pattern]
allowed-tools: Bash(grep:*)
---
!`grep -r "$ARGUMENTS" .`' grep.md
o=$(run "$d"); echo "$o" | grep -q "spliced into a" && ok "T16 quoted arg still flagged" || bad "T16" "$o"

# --- T17: no commands dir => friendly exit 0
d=$(mktemp -d /tmp/cmd.XXXXXX)
"$CL" "$d/.claude/commands" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T17 missing dir = exit 0" || bad "T17" "rc"

# --- T18: namespaced subdir command is found
d=$(newdir); mkdir -p "$d/.claude/commands/git"; printf '%s' "$CLEAN" > "$d/.claude/commands/git/summarise.md"
o=$(run "$d"); echo "$o" | grep -q "1 command file" && ok "T18 nested command discovered" || bad "T18" "$o"

# --- T19: single-file lint works
d=$(newdir); cmd "$d" "$CLEAN" summarise.md
o=$("$CL" "$d/.claude/commands/summarise.md" 2>&1); echo "$o" | grep -q "look healthy" && ok "T19 single-file lint" || bad "T19" "$o"

# --- T20: prose with 'word! `code`' (space) is NOT a bash-exec false positive
d=$(newdir); cmd "$d" '---
description: A friendly explainer command.
---
Done! `result` is shown above. Great work.' prose.md
o=$(run "$d"); echo "$o" | grep -q "look healthy" && ok "T20 no false-positive on prose" || bad "T20" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
