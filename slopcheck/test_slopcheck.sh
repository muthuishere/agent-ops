#!/usr/bin/env bash
# Tests for slopcheck — audits deps for AI-hallucination / slopsquat risk.
# Deterministic: drives the OFFLINE path (--meta <registry-metadata.json>) so no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SC="$HERE/slopcheck"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/sc.XXXXXX; }

META=$(tmp); cat > "$META" <<'JSON'
{
  "react":        {"exists": true,  "downloads": 25000000, "created": "2013-05-29", "repo": true},
  "express":      {"exists": true,  "downloads": 30000000, "created": "2010-12-29", "repo": true},
  "left-pad-helperx": {"exists": false},
  "expres":       {"exists": false},
  "tiny-obscure-thing": {"exists": true, "downloads": 12, "created": "2026-05-01", "repo": false},
  "raect":        {"exists": true,  "downloads": 30, "created": "2026-04-10", "repo": false}
}
JSON

# --- T1: a NONEXISTENT package => HIGH (hallucinated / uninstallable)
o=$("$SC" --ecosystem npm --meta "$META" left-pad-helperx 2>&1)
echo "$o" | grep -Eiq "HIGH|hallucinat|not (in|on) (the )?registr|does not exist" && ok "T1 nonexistent = HIGH" || bad "T1" "$o"

# --- T2: a real popular package => clean, no finding
o=$("$SC" --ecosystem npm --meta "$META" react 2>&1)
echo "$o" | grep -Eiq "HIGH|WARN" && bad "T2 popular pkg falsely flagged" "$o" || ok "T2 popular pkg clean"

# --- T3: exists but near-name (edit distance 1) to a popular pkg => typo/confusion WARN
o=$("$SC" --ecosystem npm --meta "$META" raect 2>&1)
echo "$o" | grep -Eiq "typo|confus|looks like|did you mean|near" && ok "T3 near-name typo flagged" || bad "T3" "$o"

# --- T4: exists but extremely low downloads => obscure WARN
o=$("$SC" --ecosystem npm --meta "$META" tiny-obscure-thing 2>&1)
echo "$o" | grep -Eiq "low|obscure|barely|downloads|rarely" && ok "T4 low-download flagged" || bad "T4" "$o"

# --- T5: exit 1 when any HIGH present, 0 when all clean
"$SC" --ecosystem npm --meta "$META" left-pad-helperx >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T5 HIGH => exit 1" || bad "T5 exit" "rc=$?"
"$SC" --ecosystem npm --meta "$META" react express >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T5b clean => exit 0" || bad "T5b exit" "rc=$?"

# --- T6: parses a package.json manifest (dependencies + devDependencies)
d=$(mktemp -d); cat > "$d/package.json" <<'JSON'
{"dependencies": {"react": "^18.0.0", "left-pad-helperx": "^1.0.0"}, "devDependencies": {"express": "^4.0.0"}}
JSON
o=$("$SC" --meta "$META" "$d/package.json" 2>&1)
echo "$o" | grep -Eq "3 npm dependenc" && echo "$o" | grep -Eiq "left-pad-helperx" && ok "T6 parses package.json (deps+devDeps)" || bad "T6" "$o"

# --- T7: parses a requirements.txt manifest (pypi ecosystem inferred)
PMETA=$(tmp); cat > "$PMETA" <<'JSON'
{"requests": {"exists": true, "downloads": 9000000, "created": "2011-02-14", "repo": true},
 "reqests":  {"exists": false}}
JSON
d=$(mktemp -d); printf 'requests==2.31.0\nreqests>=1.0\n# a comment\n' > "$d/requirements.txt"
o=$("$SC" --meta "$PMETA" "$d/requirements.txt" 2>&1)
echo "$o" | grep -Eiq "reqests" && ok "T7 parses requirements.txt" || bad "T7" "$o"

# --- T8: --json emits machine-readable verdicts
o=$("$SC" --ecosystem npm --meta "$META" --json left-pad-helperx react 2>&1)
echo "$o" | grep -Eq '"verdict"|"risk"|"findings"' && ok "T8 --json output" || bad "T8" "$o"

# --- T9: reports a summary count of risky deps
o=$("$SC" --ecosystem npm --meta "$META" left-pad-helperx expres react 2>&1)
echo "$o" | grep -Eiq "[0-9]+ of [0-9]+|risky|flagged" && ok "T9 summary count" || bad "T9" "$o"

# --- T10: a clean manifest with only popular deps => exit 0, says clean
o=$("$SC" --ecosystem npm --meta "$META" react express 2>&1)
echo "$o" | grep -Eiq "clean|no .*risk|all .*known" && ok "T10 clean manifest message" || bad "T10" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
