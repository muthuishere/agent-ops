#!/usr/bin/env bash
# Tests for leaklint — flags LEAKED SECRETS in agent OUTPUT, never printing the value.
# Deterministic + offline. The secret *values* here are SYNTHETIC fakes with realistic
# prefixes/shape; the load-bearing assertion is that leaklint detects them while NEVER
# echoing the value back (only brand prefix + length + sha256 fingerprint).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LL="$HERE/leaklint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

D=$(mktemp -d /tmp/leaklint.XXXXXX)

# synthetic fake secrets (NOT real) — built so no literal real credential lives in the test.
GH="ghp_$(printf 'A%.0s' {1..36})"                       # GitHub token shape
AWS="AKIA$(printf 'B%.0s' {1..16})"                       # AWS access key id shape
ANT="sk-ant-$(printf 'C%.0s' {1..24})"                    # Anthropic key shape

# T1: GitHub token -> PROVIDER-KEY, exit 1
printf 'token: %s\n' "$GH" > "$D/gh.txt"
"$LL" "$D/gh.txt" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T1 provider key => exit 1" || bad "T1 gh exit" "rc"
o=$("$LL" "$D/gh.txt" 2>&1); echo "$o" | grep -q "PROVIDER-KEY" && ok "T2 reports PROVIDER-KEY" || bad "T2 gh kind" "$o"

# T3 (LOAD-BEARING): the matched secret VALUE is never printed; only a redacted label is.
o=$("$LL" "$D/gh.txt" 2>&1)
if echo "$o" | grep -q "$GH"; then bad "T3 leaks the secret value" "value echoed"; else ok "T3 never prints the secret value"; fi
echo "$o" | grep -Eq "sha256:[0-9a-f]{8}" && ok "T4 shows a sha256 fingerprint" || bad "T4 fingerprint" "$o"
echo "$o" | grep -q "len=" && ok "T5 shows length, not value" || bad "T5 len" "$o"

# T6: AWS access key id detected
printf 'aws_key=%s\n' "$AWS" > "$D/aws.txt"
o=$("$LL" "$D/aws.txt" 2>&1); echo "$o" | grep -q "PROVIDER-KEY" && ok "T6 detects AWS access key id" || bad "T6 aws" "$o"

# T7: Anthropic key detected
printf 'export KEY=%s\n' "$ANT" > "$D/ant.txt"
o=$("$LL" "$D/ant.txt" 2>&1); echo "$o" | grep -q "PROVIDER-KEY" && ok "T7 detects Anthropic key" || bad "T7 ant" "$o"

# T8: PEM private-key header -> PRIVATE-KEY
printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIByyz...\n' > "$D/pem.txt"
o=$("$LL" "$D/pem.txt" 2>&1); echo "$o" | grep -q "PRIVATE-KEY" && ok "T8 detects PEM private-key header" || bad "T8 pem" "$o"

# T9: ASSIGNED-SECRET — a credential-named var set to a high-entropy literal
printf 'DATABASE_PASSWORD = "Xq7zR2vL9pK4mB1nW8tH"\n' > "$D/assign.txt"
o=$("$LL" "$D/assign.txt" 2>&1); echo "$o" | grep -q "ASSIGNED-SECRET" && ok "T9 flags assigned literal secret" || bad "T9 assign" "$o"

# T10: env-var REFERENCE (the correct pattern) is NOT a leak -> clean, exit 0
printf 'API_KEY = os.environ["API_KEY"]\nTOKEN=$GITHUB_TOKEN\n' > "$D/envref.txt"
"$LL" "$D/envref.txt" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T10 env-ref not flagged (exit 0)" || bad "T10 envref exit" "rc"

# T11: placeholder is NOT a leak -> clean
printf 'API_KEY = "YOUR_KEY_HERE"\ntoken: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' > "$D/ph.txt"
"$LL" "$D/ph.txt" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T11 placeholders not flagged (exit 0)" || bad "T11 placeholder exit" "rc"

# T12: a genuinely clean file -> exit 0 + "clean"
printf 'Deploy finished. No credentials here, just prose.\n' > "$D/clean.txt"
"$LL" "$D/clean.txt" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T12 clean file exits 0" || bad "T12 clean exit" "rc"
"$LL" "$D/clean.txt" 2>&1 | grep -qi "clean" && ok "T13 clean file reported clean" || bad "T13 clean msg" "$("$LL" "$D/clean.txt")"

# T14: --json is machine-readable AND still redacted (never a "value" key, never the secret)
o=$("$LL" --json "$D/gh.txt" 2>&1)
echo "$o" | grep -q '"redacted"' && ok "T14 --json emits redacted findings" || bad "T14 json" "$o"
if echo "$o" | grep -q "$GH"; then bad "T15 --json leaks the value" "value in json"; else ok "T15 --json never contains the value"; fi
echo "$o" | grep -q '"value"' && bad "T16 --json has a value key" "value key present" || ok "T16 --json has no value key"

# T17: --transcript scans tool_use inputs (a key baked into a Bash command is the danger case)
cat > "$D/session.jsonl" <<JSON
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"t1","input":{"command":"curl -H 'Authorization: Bearer $GH' https://api"}}]}}
JSON
o=$("$LL" --transcript "$D/session.jsonl" 2>&1); echo "$o" | grep -q "PROVIDER-KEY" && ok "T17 --transcript scans tool_use inputs" || bad "T17 transcript" "$o"

# T18: missing file -> exit 2
"$LL" "$D/nope.txt" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T18 missing file exits 2" || bad "T18 missing exit" "rc"

rm -rf "$D"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
