#!/usr/bin/env bash
# Tests for langcheck — flags contamination in LLM/agent OUTPUT text.
# Deterministic + offline: synthetic files exercising each contamination class,
# plus the dominance guard that keeps a genuinely non-Latin document clean.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LC="$HERE/langcheck"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
# write exact bytes (incl. non-ASCII) without shell-quoting surprises
mk() { python3 -c 'import sys;open(sys.argv[1],"w",encoding="utf-8").write(sys.argv[2])' "$1" "$2"; }

D=$(mktemp -d /tmp/langcheck.XXXXXX)

# T1/T2: CJK intrusion inside predominantly-English text -> SCRIPT-INTRUSION, exit 1
mk "$D/cjk.md" "$(python3 -c 'print("The build is green and ready to 你好 ship now.")')"
"$LC" "$D/cjk.md" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T1 script-intrusion exits 1" || bad "T1 cjk exit" "rc"
o=$("$LC" "$D/cjk.md" 2>&1); echo "$o" | grep -q "SCRIPT-INTRUSION" && ok "T2 reports SCRIPT-INTRUSION" || bad "T2 cjk" "$o"

# T3: a genuinely non-Latin (Cyrillic) document is NOT flagged for intrusion -> exit 0
mk "$D/ru.md" "$(python3 -c 'print("Привет мир, это полностью русский документ без латиницы вообще.")')"
"$LC" "$D/ru.md" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T3 predominantly non-Latin exits 0" || bad "T3 ru exit" "rc"
o=$("$LC" "$D/ru.md" 2>&1); echo "$o" | grep -qi "skipped" && ok "T4 non-Latin: intrusion check skipped (info)" || bad "T4 ru info" "$o"

# T5: mojibake / U+FFFD replacement char -> MOJIBAKE
mk "$D/moji.txt" "$(python3 -c 'print("totally fine line\nbroken "+chr(0xFFFD)+" here")')"
o=$("$LC" "$D/moji.txt" 2>&1); echo "$o" | grep -q "MOJIBAKE" && ok "T5 flags U+FFFD as MOJIBAKE" || bad "T5 moji" "$o"

# T6: runaway repetition (same line >= threshold in a row) -> REPETITION
mk "$D/rep.txt" "$(python3 -c 'print("\n".join(["intro"]+["loop forever"]*5+["end"]))')"
o=$("$LC" "$D/rep.txt" 2>&1); echo "$o" | grep -q "REPETITION" && ok "T6 flags runaway repetition" || bad "T6 rep" "$o"

# T7: --repeat raises the threshold so 3 repeats no longer trip the default-4 gate
mk "$D/rep3.txt" "$(python3 -c 'print("\n".join(["a"]+["dup"]*3+["b"]))')"
"$LC" --repeat 5 "$D/rep3.txt" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T7 --repeat raises threshold (clean)" || bad "T7 repeat-flag" "rc"

# T8: a genuinely clean English file -> exit 0 + "clean"
mk "$D/clean.md" "$(printf '# Title\nRun the tests, then commit and push.\n')"
"$LC" "$D/clean.md" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8 clean file exits 0" || bad "T8 clean exit" "rc"
"$LC" "$D/clean.md" 2>&1 | grep -qi "clean" && ok "T9 clean file reported clean" || bad "T9 clean msg" "$("$LC" "$D/clean.md")"

# T10: stdin scan
o=$(python3 -c 'import sys;sys.stdout.write("ok english then 世界 intrusion")' | "$LC" 2>&1)
echo "$o" | grep -q "SCRIPT-INTRUSION" && ok "T10 scans stdin" || bad "T10 stdin" "$o"

# T11: --transcript scans assistant-message text from a session jsonl
cat > "$D/session.jsonl" <<'JSON'
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All set, the report 你好 is done."}]}}
JSON
o=$("$LC" --transcript "$D/session.jsonl" 2>&1); echo "$o" | grep -q "SCRIPT-INTRUSION" && ok "T11 --transcript scans assistant text" || bad "T11 transcript" "$o"

# T12: missing file -> usage/IO error exit 2 (not 0/1)
"$LC" "$D/nope-does-not-exist.md" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T12 missing file exits 2" || bad "T12 missing exit" "rc"

rm -rf "$D"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
