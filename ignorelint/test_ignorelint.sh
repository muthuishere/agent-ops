#!/usr/bin/env bash
# Tests for ignorelint — builds throwaway repos with real files + ignore files
# and asserts on the verdict text and exit code (1 on HIGH, 0 otherwise).
# Deterministic and offline: no network, no real git needed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IL="$HERE/ignorelint"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1 -- $2"; FAIL=$((FAIL+1)); }
newdir() { d=$(mktemp -d /tmp/ign.XXXXXX); echo "$d"; }
run() { "$IL" "$1" 2>&1; }

# --- T1: a .env on disk with NO .gitignore => HIGH (unignored secret) + exit 1
d=$(newdir); printf 'X=1\n' > "$d/.env"
o=$(run "$d"); echo "$o" | grep -q "secret file '.env' is not ignored" && ok "T1 unignored .env = HIGH" || bad "T1" "$o"
"$IL" "$d" >/dev/null 2>&1; [ "$?" -eq 1 ] && ok "T2 exit 1 on high-severity" || bad "T2 exit" "rc"

# --- T3: same .env but .gitignore ignores it => clean, exit 0
d=$(newdir); printf 'X=1\n' > "$d/.env"; printf '.env\n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T3 ignored .env = clean" || bad "T3" "$o"
"$IL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T4 clean exits 0" || bad "T4 exit" "rc"

# --- T5: secret in a subdir, ignored by a dir rule => clean
d=$(newdir); mkdir -p "$d/secrets"; printf 'k\n' > "$d/secrets/app.key"; printf 'secrets/\n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T5 dir rule covers nested secret" || bad "T5" "$o"

# --- T6: secret in a subdir NOT covered => HIGH names the full path
d=$(newdir); mkdir -p "$d/config"; printf 'k\n' > "$d/config/server.pem"; printf 'node_modules/\n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "secret file 'config/server.pem' is not ignored" && ok "T6 nested unignored = HIGH" || bad "T6" "$o"

# --- T7: anchored glob ignores it (config/*.pem) => clean
d=$(newdir); mkdir -p "$d/config"; printf 'k\n' > "$d/config/server.pem"; printf 'config/*.pem\n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T7 anchored glob covers it" || bad "T7" "$o"

# --- T8: .env.example present and unignored => NOT flagged (safe variant)
d=$(newdir); printf 'X=\n' > "$d/.env.example"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T8 .env.example not a secret" || bad "T8" "$o"

# --- T9: negation re-includes a secret => HIGH
d=$(newdir); printf 'X=1\n' > "$d/.env"; printf '*.env\n!keep.env\n' > "$d/.gitignore"; printf 'X=1\n' > "$d/keep.env"
o=$(run "$d"); echo "$o" | grep -q "re-includes a secret-looking file" && ok "T9 negated secret = HIGH" || bad "T9" "$o"

# --- T10: dead re-include under an ignored directory => WARN
d=$(newdir); printf 'build/\n!build/keep.txt\n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "is dead — a parent directory is ignored" && ok "T10 dead re-include = WARN" || bad "T10" "$o"

# --- T11: ignore-everything pattern => WARN
d=$(newdir); printf '*\n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "excludes the entire tree" && ok "T11 '*' = WARN" || bad "T11" "$o"
"$IL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T12 WARN-only exits 0" || bad "T12 exit" "rc"

# --- T13: trailing-whitespace pattern => WARN
d=$(newdir); printf '.env \n' > "$d/.gitignore"
o=$(run "$d"); echo "$o" | grep -q "has trailing whitespace" && ok "T13 trailing space = WARN" || bad "T13" "$o"

# --- T14: secret git-ignored but NOT in an existing .claudeignore => WARN
d=$(newdir); printf 'X=1\n' > "$d/.env"; printf '.env\n' > "$d/.gitignore"; printf 'node_modules/\n' > "$d/.claudeignore"
o=$(run "$d"); echo "$o" | grep -q "git-ignored but not in .claudeignore" && ok "T14 agent-visible secret = WARN" || bad "T14" "$o"

# --- T15: secret in BOTH .gitignore and .claudeignore => clean
d=$(newdir); printf 'X=1\n' > "$d/.env"; printf '.env\n' > "$d/.gitignore"; printf '.env\n' > "$d/.claudeignore"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T15 mirrored into agent ignore = clean" || bad "T15" "$o"

# --- T16: comments and blanks are ignored, *.pub is not a secret
d=$(newdir); printf '# comment\n\n*.log\n' > "$d/.gitignore"; printf 'k\n' > "$d/id_rsa.pub"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T16 .pub safe, comments parsed" || bad "T16" "$o"

# --- T17: a real private key id_rsa unignored => HIGH
d=$(newdir); printf 'k\n' > "$d/id_rsa"
o=$(run "$d"); echo "$o" | grep -q "secret file 'id_rsa' is not ignored" && ok "T17 id_rsa = HIGH" || bad "T17" "$o"

# --- T18: not-a-directory arg => exit 2
"$IL" "/tmp/nope-ignorelint-$$" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "T18 bad dir = exit 2" || bad "T18" "rc"

# --- T19: empty clean repo => exit 0
d=$(newdir); printf 'node_modules/\n*.log\n' > "$d/.gitignore"; printf 'hi\n' > "$d/main.py"
o=$(run "$d"); echo "$o" | grep -q "no ignore-config gaps" && ok "T19 clean repo = no findings" || bad "T19" "$o"
"$IL" "$d" >/dev/null 2>&1; [ "$?" -eq 0 ] && ok "T20 clean repo exits 0" || bad "T20 exit" "rc"

# --- T21: a .env file with a trailing-space rule => git won't match it, so HIGH (exposed) + WARN
d=$(newdir); printf 'X=1\n' > "$d/.env"; printf '.env \n' > "$d/.gitignore"
o=$(run "$d")
echo "$o" | grep -q "secret file '.env' is not ignored" && ok "T21a trailing-space rule leaves secret exposed (HIGH)" || bad "T21a" "$o"
echo "$o" | grep -q "has trailing whitespace" && ok "T21b also warns on the trailing space" || bad "T21b" "$o"

echo "-----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
