#!/usr/bin/env bash
# Tests for agent-reach — synthetic repo + synthetic $HOME (never the real one).
# Asserts paths-only reporting, the committed-secret flag, --repo-only, exit codes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AR="$HERE/agent-reach"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

# a synthetic home with two well-known stores
HOME_SYN=$(mktemp -d); mkdir -p "$HOME_SYN/.aws" "$HOME_SYN/.ssh"
echo k > "$HOME_SYN/.aws/credentials"; echo k > "$HOME_SYN/.ssh/id_ed25519"

# a synthetic repo: .env gitignored, .pem + .npmrc committed, plus a clean source file
R=$(mktemp -d); ( cd "$R"; git init -q
  echo "S=1" > .env; echo ".env" > .gitignore
  mkdir cfg; echo x > cfg/server.pem; echo "//r/:_authToken=t" > .npmrc; echo ok > app.js ) >/dev/null

out=$(cd "$R" && AGENT_REACH_HOME="$HOME_SYN" "$AR" 2>&1); rc=$?

echo "### repo-tree detection"
echo "$out" | grep -q "\.env" && ok "T1 finds .env" || bad "T1 .env" "$out"
echo "$out" | grep -q "cfg/server.pem" && ok "T2 finds the .pem" || bad "T2 pem" "$out"
echo "$out" | grep -q "\.npmrc" && ok "T3 finds the .npmrc" || bad "T3 npmrc" "$out"
echo "$out" | grep -Eq "server.pem.*COMMITTED" && ok "T4 flags a COMMITTED secret" || bad "T4 committed" "$out"
echo "$out" | grep -Eq "\.env.*COMMITTED" && bad "T5 gitignored .env should NOT be flagged committed" "$out" || ok "T5 gitignored secret not flagged committed"

echo "### \$HOME stores (presence only)"
echo "$out" | grep -q "~/.aws/credentials" && ok "T6 finds ~/.aws/credentials" || bad "T6 aws" "$out"
echo "$out" | grep -q "~/.ssh/id_ed25519" && ok "T7 finds the SSH key" || bad "T7 ssh" "$out"

echo "### safety: never prints secret CONTENTS"
echo "$out" | grep -q "S=1" && bad "T8 leaked .env contents!" "$out" || ok "T8 does not print file contents"

echo "### summary + exit code"
echo "$out" | grep -Eq "blast radius: 5 .*2 committed" && ok "T9 summary counts (5 reachable, 2 committed)" || bad "T9 summary" "$out"
[ "$rc" -eq 1 ] && ok "T10 exit 1 when blast radius is non-empty" || bad "T10 exit" "got $rc"

echo "### --repo-only skips \$HOME"
o2=$(cd "$R" && AGENT_REACH_HOME="$HOME_SYN" "$AR" --repo-only 2>&1)
echo "$o2" | grep -q "aws/credentials" && bad "T11 --repo-only still scanned \$HOME" "$o2" || ok "T11 --repo-only skips \$HOME"

echo "### clean dir = exit 0"
C=$(mktemp -d); ( cd "$C"; git init -q; echo ok > main.go ) >/dev/null
( cd "$C" && AGENT_REACH_HOME="$(mktemp -d)" "$AR" >/dev/null 2>&1 ); [ "$?" -eq 0 ] && ok "T12 clean repo + empty home exits 0" || bad "T12 clean exit" "nonzero"

rm -rf "$HOME_SYN" "$R" "$C"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
