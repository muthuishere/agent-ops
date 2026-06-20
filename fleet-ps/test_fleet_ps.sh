#!/usr/bin/env bash
# Tests for fleet-ps — builds a synthetic ~/.claude/projects and asserts the view.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FP="$HERE/fleet-ps"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

ROOT=$(mktemp -d /tmp/fleet-ps.XXXXXX); export CLAUDE_PROJECTS_DIR="$ROOT"

# a healthy session, cwd=/work/app branch=main, just now
mkproj() { # $1=slug $2=cwd $3=branch $4=age_seconds $5=wedged(0/1)
  local d="$ROOT/$1"; mkdir -p "$d"
  python3 - "$d/s.jsonl" "$2" "$3" "$5" <<'PY'
import json,sys
path,cwd,branch,wedged=sys.argv[1:5]
rows=[{"type":"user","cwd":cwd,"gitBranch":branch,"message":{"role":"user","content":[{"type":"text","text":"hi"}]}},
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}},
      {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"x"}]}}]
if wedged=="1":
    rows.append({"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"","signature":"s"}]}})
else:
    rows.append({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}})
open(path,"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
  touch -t "$(date -v-"$4"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$(( $(date +%s) - $4 ))" +%Y%m%d%H%M.%S)" "$d/s.jsonl"
}

mkproj "-work-app"      "/work/app"      "main"          30     0   # 30s ago, healthy
mkproj "-work-api"      "/work/api"      "feat/login"    120    1   # 2m ago, WEDGED
mkproj "-old-thing"     "/old/thing"     "main"          99999  0   # ~27h ago, old

echo "### default (recent)"
out=$("$FP" 2>/dev/null)
echo "$out" | grep -q "/work/app" && ok "T1 lists a recent session" || bad "T1 recent" "$out"
echo "$out" | grep -q "old/thing" && bad "T2 old session hidden by default" "$out" || ok "T2 old session hidden by default"
echo "$out" | grep -Eq "1 wedged" && ok "T3 wedged count in header" || bad "T3 wedged count" "$out"
echo "$out" | grep -Eq "work/api.*|wedged" ; echo "$out" | grep -q "wedged" && ok "T4 flags the wedged session" || bad "T4 wedged flag" "$out"
echo "$out" | grep -q "feat/login" && ok "T5 shows git branch from transcript" || bad "T5 branch" "$out"

echo "### --all includes the old one"
"$FP" --all 2>/dev/null | grep -q "old/thing" && ok "T6 --all includes old session" || bad "T6 --all" "$("$FP" --all)"

echo "### --since filters tighter"
# 1-minute window: the 2m-old api drops out, the 30s app stays
o2=$("$FP" --since 1 2>/dev/null)
echo "$o2" | grep -q "/work/app" && ! echo "$o2" | grep -q "/work/api" && ok "T7 --since narrows the window" || bad "T7 --since" "$o2"

echo "### sorted newest-first"
"$FP" --all 2>/dev/null | grep -E "work/app|work/api|old/thing" | head -1 | grep -q "app" && ok "T8 newest session first" || bad "T8 order" "$("$FP" --all | grep -E 'work|old')"

rm -rf "$ROOT"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
