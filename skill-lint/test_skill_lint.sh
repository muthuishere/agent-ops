#!/usr/bin/env bash
# Tests for skill-lint — synthetic SKILL.md files.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SL="$HERE/skill-lint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
mkskill() { d=$(mktemp -d)/"$1"; mkdir -p "$d"; printf '%s' "$2" > "$d/SKILL.md"; echo "$d"; }

GOOD='---
name: dbmate
description: Run and create database migrations with dbmate. Use this when the user mentions migrations, schema changes, dbmate, or asks to migrate the database up or down.
---
# dbmate
Run `dbmate up`. See the docs.'
d=$(mkskill dbmate "$GOOD")
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -q "discoverable and lean" && ok "T1 a good skill is clean" || bad "T1 good" "$o"
"$SL" "$d/SKILL.md" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T2 clean skill exits 0" || bad "T2 exit" "rc"

# no frontmatter
d=$(mkskill nf "# just a heading")
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -q "no YAML frontmatter" && ok "T3 missing frontmatter = HIGH" || bad "T3 nf" "$o"
"$SL" "$d/SKILL.md" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T4 findings => exit 1" || bad "T4 exit" "rc"

# no description
d=$(mkskill nd '---
name: x
---
body')
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -q "no .description" && ok "T5 missing description = HIGH" || bad "T5 nd" "$o"

# thin description (<10 words) => HIGH
d=$(mkskill thin '---
name: thin
description: Helps with stuff sometimes.
---
b')
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -Eq "HIGH.*too thin" && ok "T6 <10-word description = HIGH" || bad "T6 thin" "$o"

# mid description (~15 words, has trigger cue) => WARN not HIGH, no trigger-cue INFO
d=$(mkskill mid '---
name: mid
description: Formats and lints Go code; use this when the user edits a Go file or asks to gofmt.
---
b')
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -Eq "WARN.*under-specified" && ok "T7 ~15-word description = WARN" || bad "T7 mid" "$o"

# description with no trigger cue => INFO
d=$(mkskill notrig '---
name: notrig
description: This reads a comma separated values file and produces a chart image plus a short written summary of the columns and totals.
---
b')
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -q "not WHEN to use it" && ok "T8 no trigger cue = INFO" || bad "T8 notrig" "$o"

# oversized body => WARN
big=$(python3 -c 'print("x "*12000)')
d=$(mkskill big "---
name: big
description: Does a thing and use it when the user asks for the thing repeatedly across many different files and folders in the project today.
---
$big")
o=$("$SL" "$d/SKILL.md" 2>&1); echo "$o" | grep -Eq "WARN.*body is" && ok "T9 oversized body = WARN" || bad "T9 big" "$o"

# stale bundled-path ref flagged; bare example filename NOT flagged
d=$(mkskill refs '---
name: refs
description: Does a thing and use it when the user asks for the thing in a file.
---
See `scripts/run.sh`, and an example `app.py`.')
o=$("$SL" "$d/SKILL.md" 2>&1)
echo "$o" | grep -q "scripts/run.sh" && ok "T10 missing bundled path flagged" || bad "T10 ref" "$o"
echo "$o" | grep -q "app.py" && bad "T11 bare example filename should NOT be flagged" "$o" || ok "T11 bare example filename not flagged"

# name != dir => INFO; pass a DIR (not the file)
d=$(mkskill realdir '---
name: different
description: Does a thing and use it when the user asks for the thing here today.
---
b')
o=$("$SL" "$(dirname "$d")/realdir" 2>&1); echo "$o" | grep -q "doesn't match the directory" && ok "T12 name!=dir = INFO (and dir arg resolves SKILL.md)" || bad "T12 namedir" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
