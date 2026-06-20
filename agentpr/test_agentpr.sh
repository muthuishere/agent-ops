#!/usr/bin/env bash
# Tests for agentpr — deterministic over a saved PR record set (--prs). No network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AP="$HERE/agentpr"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

PRS=$(mktemp /tmp/ap.XXXXXX)
cat > "$PRS" <<'JSON'
[
 {"repo":"x/y","agent":true,  "size":480,"files":12,"review":0,"ttm":3},
 {"repo":"x/y","agent":true,  "size":520,"files":14,"review":1,"ttm":6},
 {"repo":"x/y","agent":true,  "size":300,"files":8, "review":0,"ttm":2},
 {"repo":"x/y","agent":false, "size":60, "files":2, "review":4,"ttm":600},
 {"repo":"x/y","agent":false, "size":90, "files":3, "review":6,"ttm":1440},
 {"repo":"x/y","agent":false, "size":40, "files":1, "review":3,"ttm":300}
]
JSON

# --- T1: reports both groups
o=$("$AP" --prs "$PRS" 2>&1)
echo "$o" | grep -Eiq "agent" && echo "$o" | grep -Eiq "human" && ok "T1 reports agent + human" || bad "T1" "$o"

# --- T2: detects agent PRs are larger (median size 480 vs 60 = 8x)
o=$("$AP" --prs "$PRS" --json 2>&1)
echo "$o" | python3 -c 'import sys,json;d=json.load(sys.stdin)["summary"];sys.exit(0 if d["agent"]["median_size"]>d["human"]["median_size"]*3 else 1)' && ok "T2 agent PRs measurably larger" || bad "T2" "$o"

# --- T3: rubber-stamp rate higher for agent (2 of 3 = 67% vs 0%)
echo "$o" | python3 -c 'import sys,json;d=json.load(sys.stdin)["summary"];sys.exit(0 if d["agent"]["rubber_stamped_pct"]>d["human"]["rubber_stamped_pct"] else 1)' && ok "T3 agent rubber-stamp rate higher" || bad "T3" "$o"

# --- T4: human PRs drew more review comments
echo "$o" | python3 -c 'import sys,json;d=json.load(sys.stdin)["summary"];sys.exit(0 if d["human"]["median_review"]>d["agent"]["median_review"] else 1)' && ok "T4 humans get more review comments" || bad "T4" "$o"

# --- T5: human-readable verdict names the comparison
o=$("$AP" --prs "$PRS" 2>&1)
echo "$o" | grep -Eiq "larger|x larger|rubber|fewer review" && ok "T5 verdict names the gap" || bad "T5" "$o"

# --- T6: --json structure
o=$("$AP" --prs "$PRS" --json 2>&1)
echo "$o" | grep -Eq '"summary"' && echo "$o" | grep -Eq '"rubber_stamped_pct"' && ok "T6 --json fields" || bad "T6" "$o"

# --- T7: only-agent corpus => friendly 'need both' message, no crash
ONE=$(mktemp /tmp/ap.XXXXXX); printf '[{"repo":"a/b","agent":true,"size":100,"files":3,"review":0,"ttm":5}]' > "$ONE"
o=$("$AP" --prs "$ONE" 2>&1)
echo "$o" | grep -Eiq "need both|found" && ok "T7 single-group handled" || bad "T7" "$o"

# --- T8: empty corpus => no crash, exit 0
E=$(mktemp /tmp/ap.XXXXXX); printf '[]' > "$E"
"$AP" --prs "$E" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T8 empty exit 0" || bad "T8" "rc=$?"

# --- T9: rubber-stamp requires BOTH zero review AND <10min (a 0-review but slow PR is not stamped)
SLOW=$(mktemp /tmp/ap.XXXXXX)
printf '[{"repo":"a/b","agent":true,"size":100,"files":3,"review":0,"ttm":500},{"repo":"a/b","agent":false,"size":10,"files":1,"review":2,"ttm":20}]' > "$SLOW"
o=$("$AP" --prs "$SLOW" --json 2>&1)
echo "$o" | python3 -c 'import sys,json;d=json.load(sys.stdin)["summary"];sys.exit(0 if d["agent"]["rubber_stamped_pct"]==0 else 1)' && ok "T9 slow 0-review PR not rubber-stamped" || bad "T9" "$o"

# --- T10: when BOTH groups are heavily rubber-stamped, the verdict says so (not agent-vs-human)
BOTH=$(mktemp /tmp/ap.XXXXXX)
cat > "$BOTH" <<'JSON'
[{"repo":"a/b","agent":true,"size":40,"files":1,"review":0,"ttm":1},
 {"repo":"a/b","agent":true,"size":50,"files":1,"review":0,"ttm":2},
 {"repo":"a/b","agent":false,"size":45,"files":1,"review":0,"ttm":1},
 {"repo":"a/b","agent":false,"size":55,"files":2,"review":0,"ttm":3}]
JSON
o=$("$AP" --prs "$BOTH" 2>&1)
echo "$o" | grep -Eiq "rubber-stamps everything|not agent-vs-human|self-merge" && ok "T10 both-high verdict surfaces self-merge culture" || bad "T10" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
