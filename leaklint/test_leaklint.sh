#!/usr/bin/env bash
# Tests for leaklint — flags leaked secrets in agent OUTPUT, redact-by-design
# (never prints the secret value). Deterministic, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LL="$HERE/leaklint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
tmp() { mktemp /tmp/ll.XXXXXX; }

# --- T1: clean text => exit 0, no secrets
o=$(printf 'export API_BASE=https://api.example.com   # no secret here\n' | "$LL" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T1 clean text passes" || bad "T1" "$o (rc=$rc)"

# --- T2: a GitHub token => PROVIDER-KEY, exit 1
TOKEN="ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
f=$(tmp); printf 'token=%s\n' "$TOKEN" > "$f"
o=$("$LL" "$f" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "PROVIDER-KEY"; } && ok "T2 provider key detected" || bad "T2" "$o (rc=$rc)"

# --- T3: THE load-bearing rule — the full secret value is NEVER printed
echo "$o" | grep -qF "$TOKEN" && bad "T3 redaction" "leaklint printed the raw secret!" || ok "T3 secret value redacted (only prefix+fingerprint)"
rm -f "$f"

# --- T4: a PEM private-key header => PRIVATE-KEY, exit 1
f=$(tmp); printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEpANROTArealKEYbytes\n-----END RSA PRIVATE KEY-----\n' > "$f"
o=$("$LL" "$f" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "PRIVATE-KEY"; } && ok "T4 PEM private key detected" || bad "T4" "$o (rc=$rc)"
rm -f "$f"

# --- T5: a NAME=high-entropy-literal assignment => ASSIGNED-SECRET, exit 1
f=$(tmp); printf 'API_TOKEN = "x8Qz3vLmN0pR7sT2wY5bU1cD4eF6gH9j"\n' > "$f"
o=$("$LL" "$f" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$o" | grep -q "ASSIGNED-SECRET"; } && ok "T5 assigned high-entropy secret detected" || bad "T5" "$o (rc=$rc)"
rm -f "$f"

# --- T6: an env-var reference (NOT a literal) is NOT flagged (no false positive)
f=$(tmp); printf 'API_TOKEN = os.environ["API_TOKEN"]\n' > "$f"
o=$("$LL" "$f" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T6 env-var reference not flagged (no false positive)" || bad "T6" "$o (rc=$rc)"
rm -f "$f"

echo "----"; echo "leaklint: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
