#!/usr/bin/env bash
# Tests for agent-frisk — synthetic files carrying each hidden-injection vector.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AF="$HERE/agent-frisk"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
mk() { python3 -c 'import sys;open(sys.argv[1],"w",encoding="utf-8").write(sys.argv[2])' "$1" "$2"; }

D=$(mktemp -d /tmp/agent-frisk.XXXXXX)

# zero-width joiner hiding inside otherwise-normal text
mk "$D/zw.md" "$(python3 -c 'print("hello"+chr(0x200D)+"world")')"
"$AF" "$D/zw.md" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T1 flags zero-width (exit 1)" || bad "T1 zw exit" "rc"
o=$("$AF" "$D/zw.md" 2>&1); echo "$o" | grep -q "U+200D" && ok "T2 reports the ZWJ codepoint" || bad "T2 zw cp" "$o"

# bidi override (Trojan Source)
mk "$D/bidi.txt" "$(python3 -c 'print("name"+chr(0x202E)+"txt.exe")')"
o=$("$AF" "$D/bidi.txt" 2>&1); echo "$o" | grep -qi "Trojan Source" && ok "T3 flags bidi override as Trojan Source" || bad "T3 bidi" "$o"

# Unicode Tag payload (hidden LLM instruction channel)
mk "$D/tag.md" "$(python3 -c 'print("ok"+"".join(chr(0xE0000+ord(c)) for c in "hi"))')"
o=$("$AF" "$D/tag.md" 2>&1); echo "$o" | grep -qi "unicode-tag" && ok "T4 flags Unicode Tag codepoints" || bad "T4 tag" "$o"

# a genuinely clean file -> exit 0, "clean"
mk "$D/clean.md" "$(printf '# Title\nrun npm test, then commit.\n')"
"$AF" "$D/clean.md" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T5 clean file exits 0" || bad "T5 clean exit" "rc"
"$AF" "$D/clean.md" 2>&1 | grep -q "clean" && ok "T6 clean file reported clean" || bad "T6 clean msg" "$("$AF" "$D/clean.md")"

# line:col reporting
mk "$D/loc.md" "$(python3 -c 'print("line1\nab"+chr(0x200B)+"cd")')"
o=$("$AF" "$D/loc.md" 2>&1); echo "$o" | grep -qE "2:3 +U\+200B" && ok "T7 reports line:col" || bad "T7 loc" "$o"

# --strip removes the hidden chars + writes a backup + result is clean
cp "$D/tag.md" "$D/strip.md"
"$AF" --strip "$D/strip.md" >/dev/null 2>&1
[ -f "$D/strip.md.bak" ] && ok "T8 --strip writes a .bak" || bad "T8 bak" "no backup"
"$AF" "$D/strip.md" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T9 stripped file is now clean" || bad "T9 stripped" "still flagged"
# the visible text survives the strip
grep -q "ok" "$D/strip.md" && ok "T10 --strip keeps the visible text" || bad "T10 visible" "lost text"

# stdin scan
o=$(python3 -c 'import sys;sys.stdout.write("x"+chr(0x202E)+"y")' | "$AF" - 2>&1); echo "$o" | grep -q "U+202E" && ok "T11 scans stdin" || bad "T11 stdin" "$o"

rm -rf "$D"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
