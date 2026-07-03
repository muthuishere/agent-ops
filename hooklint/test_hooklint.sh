#!/usr/bin/env bash
# Tests for hooklint — synthetic .claude/settings.json hook shapes.
# Deterministic and offline: every case is a hand-built settings blob; we assert
# on the verdict text and the exit code (1 on HIGH, 0 otherwise).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HL="$HERE/hooklint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
cfg() { f=$(mktemp /tmp/hook.XXXXXX); printf '%s' "$1" > "$f"; echo "$f"; }
run() { "$HL" "$1" 2>&1; }   # capture (tool exits 1 on HIGH; avoid pipefail-into-grep)

# --- T1: mis-cased event name => HIGH (silently never fires) + exit 1
f=$(cfg '{"hooks":{"PreTooluse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "mis-cased.*PreToolUse" && ok "T1 mis-cased event = HIGH" || bad "T1" "$o"
"$HL" "$f" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T2 exit 1 on high-severity" || bad "T2 exit" "rc"

# --- T3: unknown event name => HIGH
f=$(cfg '{"hooks":{"OnEveryThing":[{"matcher":"*","hooks":[{"type":"command","command":"echo hi"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "not a real Claude Code event" && ok "T3 unknown event = HIGH" || bad "T3" "$o"

# --- T4: destructive command auto-runs => HIGH
f=$(cfg '{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"rm -rf ./build"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "destructive command (rm -rf)" && ok "T4 rm -rf = HIGH" || bad "T4" "$o"

# --- T5: secret-echo => HIGH
f=$(cfg '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo $OPENAI_API_KEY >> log"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "prints environment secrets" && ok "T5 secret echo = HIGH" || bad "T5" "$o"

# --- T6: hard-coded secret literal => HIGH
f=$(cfg '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"curl -H \"x: ghp_abcdefghijklmnopqrstuvwxyz0123\" h"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "hard-coded secret-looking literal" && ok "T6 secret literal = HIGH" || bad "T6" "$o"

# --- T7: clean, scoped, valid config => no findings, exit 0
f=$(cfg '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./scripts/check.sh"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "no hook footguns found" && ok "T7 clean config = no findings" || bad "T7" "$o"
"$HL" "$f" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8 clean config exits 0" || bad "T8 exit" "rc"

# --- T9: blanket PreToolUse matcher => WARN (not HIGH), exit 0
f=$(cfg '{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"./guard.sh"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "runs on EVERY tool call" && ok "T9 blanket matcher = WARN" || bad "T9" "$o"
"$HL" "$f" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T10 WARN-only exits 0" || bad "T10 exit" "rc"

# --- T11: flat/legacy shape (missing matcher/hooks wrapper) => HIGH
f=$(cfg '{"hooks":{"PreToolUse":[{"type":"command","command":"echo hi"}]}}')
o=$(run "$f"); echo "$o" | grep -q "missing its matcher/hooks wrapper" && ok "T11 flat shape = HIGH" || bad "T11" "$o"

# --- T12: wrong entry type => WARN
f=$(cfg '{"hooks":{"Notification":[{"matcher":"","hooks":[{"type":"webhook","command":"x"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "type 'webhook'" && ok "T12 non-command type = WARN" || bad "T12" "$o"

# --- T13: empty command => WARN
f=$(cfg '{"hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"  "}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "empty command" && ok "T13 empty command = WARN" || bad "T13" "$o"

# --- T14: invalid matcher regex => WARN
f=$(cfg '{"hooks":{"PreToolUse":[{"matcher":"Bash(","hooks":[{"type":"command","command":"echo hi"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "not a valid regex" && ok "T14 invalid matcher = WARN" || bad "T14" "$o"

# --- T15: network egress in a hook => WARN (not a curl|sh)
f=$(cfg '{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"curl https://hooks.example.com/notify"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "makes a network call" && ok "T15 egress = WARN" || bad "T15" "$o"

# --- T16: Stop hook present => INFO loop note
f=$(cfg '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"./done.sh"}]}]}}')
o=$(run "$f"); echo "$o" | grep -q "guard against stop-loops" && ok "T16 Stop = INFO loop note" || bad "T16" "$o"

# --- T17: no hooks key => clean baseline, exit 0
f=$(cfg '{"permissions":{"allow":["Bash(git status)"]}}')
o=$(run "$f"); echo "$o" | grep -q "no hooks configured" && ok "T17 no hooks = clean baseline" || bad "T17" "$o"
"$HL" "$f" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T18 baseline exits 0" || bad "T18 exit" "rc"

# --- T19: missing file => safe baseline, exit 0
"$HL" "/tmp/does-not-exist-hooklint-$$.json" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T19 missing file = exit 0" || bad "T19" "rc"

# --- T20: malformed JSON => exit 2
f=$(cfg '{"hooks": {')
"$HL" "$f" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T20 bad JSON = exit 2" || bad "T20" "rc"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
