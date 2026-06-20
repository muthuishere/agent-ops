#!/usr/bin/env bash
# Tests for review-brief — synthetic single-task transcripts.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RB="$HERE/review-brief"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }

# build a transcript from a python spec
mkt() { python3 - "$@"; }

# --- a "good" session: reads before editing, writes a new test, runs tests AFTER the edit ---
good=$(mktemp)
python3 - "$good" <<'PY'
import json,sys
def a(*b): return {"type":"assistant","message":{"role":"assistant","content":list(b)}}
def tool(n,**i): return {"type":"tool_use","name":n,"input":i}
rows=[
 {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add input validation to the parser"}]}},
 a(tool("Read",file_path="/app/parser.js")),
 {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"..."}]}},
 a(tool("Edit",file_path="/app/parser.js")),
 a(tool("Write",file_path="/app/parser.test.js")),
 a(tool("Bash",command="npm test")),
 a({"type":"text","text":"Validation added; tests pass."}),
]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
out=$("$RB" "$good")
echo "### good session"
echo "$out" | grep -q "Add input validation to the parser" && ok "T1 extracts the intent" || bad "T1 intent" "$out"
echo "$out" | grep -Eq "parser.js.*read before editing" && ok "T2 read-then-edit = informed" || bad "T2 informed" "$out"
echo "$out" | grep -Eq "parser.test.js.*created / rewritten" && ok "T3 a new Write is 'created', not flagged" || bad "T3 write" "$out"
echo "$out" | grep -q "npm test" && ok "T4 lists the test command" || bad "T4 test cmd" "$out"
echo "$out" | grep -q "self-verified" && ok "T5 tests-after-last-edit = self-verified" || bad "T5 verified" "$out"
echo "$out" | grep -q "Reviewer focus" && bad "T6 clean session should have no reviewer-focus line" "$out" || ok "T6 no reviewer-focus on a clean session"

# --- a "risky" session: edits an existing file WITHOUT reading, no tests after ---
risky=$(mktemp)
python3 - "$risky" <<'PY'
import json,sys
def a(*b): return {"type":"assistant","message":{"role":"assistant","content":list(b)}}
def tool(n,**i): return {"type":"tool_use","name":n,"input":i}
rows=[
 {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Tweak the config"}]}},
 a(tool("Bash",command="npm test")),                 # tests run BEFORE the edit
 {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}},
 a(tool("Edit",file_path="/app/config.js")),         # edited, never read
]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
out=$("$RB" "$risky")
echo "### risky session"
echo "$out" | grep -Eq "config.js.*edited without reading first" && ok "T7 edit-without-read flagged" || bad "T7 blind" "$out"
echo "$out" | grep -q "verify it yourself" && ok "T8 no tests after last edit = unverified" || bad "T8 unverified" "$out"
echo "$out" | grep -q "Reviewer focus" && ok "T9 risky session gets a reviewer-focus line" || bad "T9 focus" "$out"
echo "$out" | grep -q "edited without reading first" && ok "T10 reviewer-focus names the blind edit" || bad "T10" "$out"

# --- no edits at all ---
noedit=$(mktemp)
python3 - "$noedit" <<'PY'
import json,sys
rows=[{"type":"user","message":{"role":"user","content":[{"type":"text","text":"explain the code"}]}},
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a.py"}}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
"$RB" "$noedit" | grep -q "no file edits" && ok "T11 read-only session reported as no edits" || bad "T11 noedit" "$("$RB" "$noedit")"

rm -f "$good" "$risky" "$noedit"
echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
