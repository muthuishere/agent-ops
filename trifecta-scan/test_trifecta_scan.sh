#!/usr/bin/env bash
# Tests for trifecta-scan — synthetic agent configs.
# The contract: classify each granted capability into legs {private, untrusted, exfil}
# across .mcp.json + .claude/settings.json, and flag when ALL THREE are reachable
# in one session (Simon Willison's "lethal trifecta").
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TS="$HERE/trifecta-scan"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
mk()  { d=$(mktemp -d /tmp/tri.XXXXXX); echo "$d"; }   # a scratch project dir
run() { "$TS" "$1" 2>&1; }

# --- T1: the textbook trifecta — fs (private) + fetch (untrusted+exfil) => COMPLETE, exit 1
d=$(mk)
printf '%s' '{"mcpServers":{"filesystem":{"command":"npx","args":["-y","@mcp/server-fs","./p"]},"fetch":{"command":"npx","args":["-y","@mcp/server-fetch"]}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eq "HIGH.*LETHAL TRIFECTA COMPLETE" && ok "T1 fs+fetch = trifecta complete" || bad "T1" "$o"
"$TS" "$d" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T1b complete trifecta exits 1" || bad "T1b exit" "rc=$?"

# --- T2: only private + untrusted, NO exfil => NOT complete, exit 0
d=$(mk)
printf '%s' '{"mcpServers":{"filesystem":{"command":"x","args":["./p"]},"brave-search":{"command":"x"}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -q "LETHAL TRIFECTA COMPLETE" && bad "T2 false positive (no exfil)" "$o" || ok "T2 two legs only = not complete"
"$TS" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T2b incomplete trifecta exits 0" || bad "T2b exit" "rc=$?"

# --- T3: the single-tool sink — fetch is BOTH untrusted AND exfil (one tool, two legs)
d=$(mk)
printf '%s' '{"mcpServers":{"fetch":{"command":"x"}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eiq "untrusted.*exfil|both" && ok "T3 fetch carries untrusted+exfil" || bad "T3" "$o"

# --- T4: Read + WebFetch via settings.json allowlist alone completes the trifecta
#         (Read=private, WebFetch=untrusted+exfil) — no MCP servers at all
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Read","WebFetch"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "HIGH.*LETHAL TRIFECTA COMPLETE" && ok "T4 Read+WebFetch (builtins) = trifecta" || bad "T4" "$o"

# --- T5: Bash alone carries all three legs (read anything, curl in, curl out)
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Bash"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "HIGH.*LETHAL TRIFECTA COMPLETE" && ok "T5 Bash alone = trifecta" || bad "T5" "$o"

# --- T6: a single private-only tool => not complete, and reports the missing legs
d=$(mk)
printf '%s' '{"mcpServers":{"postgres":{"command":"x"}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eiq "missing|untrusted|exfil" && ok "T6 names the missing legs" || bad "T6" "$o"
echo "$o" | grep -q "LETHAL TRIFECTA COMPLETE" && bad "T6b false positive" "$o" || ok "T6b single private tool not complete"

# --- T7: each leg is attributed to the right capabilities in the breakdown
d=$(mk)
printf '%s' '{"mcpServers":{"gmail":{"command":"x"},"slack":{"command":"x"}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eiq "gmail" && ok "T7 lists the capability names" || bad "T7" "$o"

# --- T8: empty / no config => friendly, exit 0
d=$(mk)
o=$(run "$d"); echo "$o" | grep -Eiq "no .* config|nothing to scan|no capabilities" && ok "T8 empty dir is friendly" || bad "T8" "$o"
"$TS" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8b empty exits 0" || bad "T8b exit" "rc=$?"

# --- T9: invalid JSON => HIGH, exit 1
d=$(mk)
printf '%s' '{"mcpServers": {' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eq "HIGH.*invalid JSON|HIGH.*parse" && ok "T9 invalid JSON = HIGH" || bad "T9" "$o"

# --- T10: github MCP is BOTH private (private repos) AND untrusted (outside issues/PRs)
d=$(mk)
printf '%s' '{"mcpServers":{"github":{"command":"x"}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eiq "github" && ok "T10 github classified" || bad "T10" "$o"

# --- T11: settings.json with scoped Bash(git push:*) still counts as exfil
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Read","Bash(git push:*)"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "LETHAL TRIFECTA COMPLETE" && ok "T11 Read + git-push = trifecta" || bad "T11" "$o"

# --- T12: defuse advice present when complete (rule of two)
d=$(mk)
printf '%s' '{"mcpServers":{"filesystem":{"command":"x","args":["./p"]},"fetch":{"command":"x"}}}' > "$d/.mcp.json"
o=$(run "$d"); echo "$o" | grep -Eiq "rule of two|break any one|remove one|defuse|drop " && ok "T12 gives defuse advice" || bad "T12" "$o"

# --- T13: deny-awareness — denying the exfil tool defuses the trifecta, exit 0
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Read","WebFetch"],"deny":["WebFetch"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -q "LETHAL TRIFECTA COMPLETE" && bad "T13 deny not honored" "$o" || ok "T13 deny WebFetch defuses trifecta"
"$TS" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T13b defused exits 0" || bad "T13b exit" "rc=$?"

# --- T14: denying a WHOLE MCP server (mcp__fetch__*) removes it from the capability set
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"mcpServers":{"filesystem":{"command":"x","args":["./p"]},"fetch":{"command":"x"}}}' > "$d/.mcp.json"
printf '%s' '{"permissions":{"deny":["mcp__fetch__*"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -q "LETHAL TRIFECTA COMPLETE" && bad "T14 whole-server deny not honored" "$o" || ok "T14 deny whole fetch server defuses"

# --- T15: a SPECIFIC sub-tool deny must NOT falsely declare safe (err toward warning)
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"mcpServers":{"filesystem":{"command":"x","args":["./p"]},"github":{"command":"x"}}}' > "$d/.mcp.json"
printf '%s' '{"permissions":{"deny":["mcp__github__create_pull_request"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "LETHAL TRIFECTA COMPLETE" && ok "T15 specific sub-deny does NOT create false-safe" || bad "T15 false-safe from sub-deny" "$o"

# --- T16: a scoped Bash deny (Bash(curl:*)) must NOT drop Bash entirely
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Bash"],"deny":["Bash(curl:*)"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "LETHAL TRIFECTA COMPLETE" && ok "T16 scoped Bash deny keeps Bash flagged" || bad "T16 scoped deny dropped whole Bash" "$o"

# --- T17: bypass mode (no allowlist) means EVERY tool is granted -> trifecta complete
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"skipDangerousModePermissionPrompt":true}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "LETHAL TRIFECTA COMPLETE" && ok "T17 bypass-mode = trifecta complete" || bad "T17" "$o"
echo "$o" | grep -Eiq "bypass|unrestricted|every tool" && ok "T17b names the bypass cause" || bad "T17b" "$o"

# --- T18: defaultMode bypassPermissions is the same as the skip flag
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"defaultMode":"bypassPermissions"}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -Eq "LETHAL TRIFECTA COMPLETE" && ok "T18 defaultMode bypass = trifecta" || bad "T18" "$o"

# --- T19: bypass flag but an EXPLICIT allowlist is present -> honor the allowlist, not bypass
d=$(mk); mkdir -p "$d/.claude"
printf '%s' '{"skipDangerousModePermissionPrompt":true,"permissions":{"allow":["Read"]}}' > "$d/.claude/settings.json"
o=$(run "$d"); echo "$o" | grep -q "LETHAL TRIFECTA COMPLETE" && bad "T19 explicit allowlist ignored under bypass flag" "$o" || ok "T19 explicit allowlist overrides bypass synth"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
