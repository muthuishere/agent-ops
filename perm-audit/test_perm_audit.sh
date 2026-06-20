#!/usr/bin/env bash
# Tests for perm-audit — synthetic .claude/settings.json with various risk shapes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PA="$HERE/perm-audit"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
cfg() { f=$(mktemp /tmp/perm.XXXXXX); printf '%s' "$1" > "$f"; echo "$f"; }
run() { "$PA" "$1" 2>&1; }   # capture (tool exits 1 on HIGH; avoid pipefail-into-grep)

f=$(cfg '{"defaultMode":"bypassPermissions","permissions":{"allow":["Bash(*)"]}}')
o=$(run "$f"); echo "$o" | grep -q "CRITICAL.*bypassPermissions" && ok "T1 bypassPermissions = CRITICAL" || bad "T1" "$o"
"$PA" "$f" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T2 exit 1 on high-severity" || bad "T2 exit" "rc"

f=$(cfg '{"defaultMode":"acceptEdits","permissions":{"allow":["Bash(npm test *)"],"deny":["Read(./.env)"]}}')
o=$(run "$f"); echo "$o" | grep -q "WARN.*acceptEdits" && ok "T3 acceptEdits = WARN" || bad "T3" "$o"

f=$(cfg '{"permissions":{"allow":["Bash(*)"],"deny":["Read(./.env)"]}}')
o=$(run "$f"); echo "$o" | grep -q "HIGH.*Bash.*auto-approves ALL Bash" && ok "T4 Bash(*) = HIGH" || bad "T4" "$o"

# scoped Bash must NOT be flagged as broad
f=$(cfg '{"permissions":{"allow":["Bash(npm test *)","Bash(git status)","Read(./src/**)"],"deny":["Read(./.env)","Read(./secrets/**)"]}}')
o=$(run "$f"); echo "$o" | grep -q "no over-permissive" && ok "T5 scoped allows are clean (no false positive)" || bad "T5" "$o"
"$PA" "$f" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T6 clean config exits 0" || bad "T6 exit" "rc"

f=$(cfg '{"permissions":{"allow":["Read(**)"],"deny":["Read(./.env)"]}}')
o=$(run "$f"); echo "$o" | grep -q "WARN.*Read.*auto-approves ALL Read" && ok "T7 Read(**) = WARN" || bad "T7" "$o"

f=$(cfg '{"permissions":{"allow":["WebFetch"],"deny":["Read(./.env)"]}}')
o=$(run "$f"); echo "$o" | grep -qE "WebFetch" && ok "T8 broad WebFetch flagged" || bad "T8" "$o"

f=$(cfg '{"enableAllProjectMcpServers":true,"permissions":{"allow":["Bash(git status)"],"deny":["Read(./.env)"]}}')
o=$(run "$f"); echo "$o" | grep -q "enableAllProjectMcpServers" && ok "T9 enableAllProjectMcpServers flagged" || bad "T9" "$o"

# broad bash + NO secret deny => HIGH 'no deny rules'
f=$(cfg '{"permissions":{"allow":["Bash(*)"],"deny":[]}}')
o=$(run "$f"); echo "$o" | grep -q "HIGH.*no deny rules protecting secrets" && ok "T10 missing secret-deny = HIGH when bash broad" || bad "T10" "$o"
# secret deny present => that finding does NOT fire
f=$(cfg '{"permissions":{"allow":["Bash(git log)"],"deny":["Read(./.env)","Read(~/.ssh/**)"]}}')
o=$(run "$f"); echo "$o" | grep -q "no deny rules protecting secrets" && bad "T11 should not flag when secrets are denied" "$o" || ok "T11 secret-deny coverage silences the finding"

# missing settings.json => safe baseline, exit 0
"$PA" "/tmp/does-not-exist-$$.json" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T12 missing settings = safe baseline (exit 0)" || bad "T12" "rc"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
