#!/usr/bin/env bash
# Tests for mcpfunnel — deterministic core (classify / composition / funnel) over a
# synthetic registry dump, plus offline --registry analysis. No network, no boot.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MF="$HERE/mcpfunnel"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

REG=$(mktemp /tmp/mf.XXXXXX)
cat > "$REG" <<'JSON'
[
 {"server":{"name":"a/remote1","remotes":[{"type":"streamable-http","url":"https://x"}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":true}}},
 {"server":{"name":"a/remote2","remotes":[{"type":"streamable-http","url":"https://y"}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":true}}},
 {"server":{"name":"a/remote3","remotes":[{"type":"streamable-http","url":"https://z"}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":true}}},
 {"server":{"name":"b/npmsrv","packages":[{"registryType":"npm","identifier":"@x/srv","version":"1.0.0","transport":{"type":"stdio"}}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":true}}},
 {"server":{"name":"c/pysrv","packages":[{"registryType":"pypi","identifier":"mcp-thing","version":"0.2.0","transport":{"type":"stdio"}}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":true}}},
 {"server":{"name":"d/docker","packages":[{"registryType":"oci","identifier":"ghcr.io/x/srv"}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":true}}},
 {"server":{"name":"b/npmsrv","packages":[{"registryType":"npm","identifier":"@x/srv","version":"0.9.0"}]},"_meta":{"io.modelcontextprotocol.registry/official":{"isLatest":false}}}
]
JSON

# --- T1: dedupes to latest (the npmsrv appears twice; isLatest=true wins) => 6 unique
o=$("$MF" --registry "$REG" 2>&1)
echo "$o" | grep -Eq "6 unique servers" && ok "T1 dedupes to 6 unique latest" || bad "T1" "$o"

# --- T2: composition counts remote/npm/pypi/oci
echo "$o" | grep -Eq "3 .*remote" && ok "T2 counts 3 remote" || bad "T2 remote" "$o"
echo "$o" | grep -Eiq "npm" && echo "$o" | grep -Eiq "pypi" && ok "T2b counts npm + pypi" || bad "T2b" "$o"

# --- T3: the headline — installable vs remote-only split
echo "$o" | grep -Eiq "installable" && echo "$o" | grep -Eiq "remote-only|hosted" && ok "T3 installable-vs-remote headline" || bad "T3" "$o"

# --- T4: 2 of 6 are installable (npm + pypi)
echo "$o" | grep -Eq "2 of 6" && ok "T4 2 of 6 installable" || bad "T4" "$o"

# --- T5: --json has composition + funnel
o=$("$MF" --registry "$REG" --json 2>&1)
echo "$o" | grep -Eq '"composition"' && echo "$o" | grep -Eq '"funnel"' && ok "T5 --json structure" || bad "T5" "$o"
echo "$o" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d["composition"].get("remote")==3 and d["funnel"]["installable"]==2 else 1)' && ok "T5b --json counts correct" || bad "T5b" "$o"

# --- T6: classify handles a remotes-only record as remote, npm pkg as npm (via json detail)
o=$("$MF" --registry "$REG" --json 2>&1)
echo "$o" | python3 -c 'import sys,json; d=json.load(sys.stdin); c=d["composition"]; sys.exit(0 if c.get("npm")==1 and c.get("pypi")==1 and c.get("oci")==1 else 1)' && ok "T6 classify npm/pypi/oci each = 1" || bad "T6" "$o"

# --- T7: an empty registry => friendly, no crash
E=$(mktemp /tmp/mf.XXXXXX); printf '[]' > "$E"
"$MF" --registry "$E" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T7 empty registry exit 0" || bad "T7" "rc=$?"

# --- T8: malformed registry json => nonzero exit (not a silent wrong answer)
B=$(mktemp /tmp/mf.XXXXXX); printf '{bad' > "$B"
"$MF" --registry "$B" >/dev/null 2>&1; [ "$?" -ne 0 ] && ok "T8 malformed json nonzero exit" || bad "T8" "rc"

# --- T9: --funnel-results displays a cached boot run deterministically (no relaunch)
FR=$(mktemp /tmp/mf.XXXXXX)
cat > "$FR" <<'JSON'
[{"name":"b/npmsrv","kind":"npm","identifier":"@x/srv","resolves":true,"boot":"speaks:5"},
 {"name":"c/pysrv","kind":"pypi","identifier":"mcp-thing","resolves":true,"boot":"no-handshake"}]
JSON
o=$("$MF" --registry "$REG" --funnel-results "$FR" 2>&1)
echo "$o" | grep -Eiq "handshake" && echo "$o" | grep -Eq "1" && ok "T9 cached funnel: 1 of 2 speaks" || bad "T9" "$o"
echo "$o" | grep -Eiq "out of the box|no config" && ok "T9b funnel framing present" || bad "T9b" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
