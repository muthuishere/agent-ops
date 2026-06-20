#!/usr/bin/env bash
# measure-cache.sh — a 2-call A/B that PROVES prompt caching engaged, against
# the real Claude API. Call 1 writes the cache; call 2 (identical prefix,
# different trailing question) reads it. We save the raw `usage` from each so
# the numbers in the post are measured, not asserted.
#
#   call 1 -> cache_creation_input_tokens > 0   (you paid the 1.25x write)
#   call 2 -> cache_read_input_tokens   ~= prefix, cache_creation == 0
#
# Requires ANTHROPIC_API_KEY. Minimal spend (~2 small calls). Never prints the key.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
MODEL="${MODEL:-claude-opus-4-8}"
: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY}"
[ -f prefix.txt ] || { echo "missing prefix.txt (run gen first)"; exit 2; }

req() {  # $1 = question text -> request body on stdout
  jq -n --rawfile p prefix.txt --arg q "$1" --arg m "$MODEL" '{
    model: $m, max_tokens: 16,
    system: [{type:"text", text:$p, cache_control:{type:"ephemeral"}}],
    messages: [{role:"user", content:$q}]
  }'
}

call() {  # $1 = question, $2 = out file
  curl -sS https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(req "$1")" > "$2"
  if jq -e .error "$2" >/dev/null 2>&1; then
    echo "API error:"; jq .error "$2"; exit 1
  fi
}

echo "== token count (free) =="
curl -sS https://api.anthropic.com/v1/messages/count_tokens \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" -d "$(req 'How long is express shipping?')" \
  | jq '{prefix_input_tokens: .input_tokens}'

echo "== call 1: cache WRITE =="
call "How long is express shipping?" resp1.json
jq '.usage' resp1.json | tee write-usage.json

echo "== (waiting for the cache to become readable) =="
sleep 3

echo "== call 2: cache READ (same prefix, different question) =="
call "What is the returns window?" resp2.json
jq '.usage' resp2.json | tee read-usage.json

# Combined, committed summary so the post/demo cite real numbers without re-spending.
jq -n --slurpfile w write-usage.json --slurpfile r read-usage.json --arg m "$MODEL" '{
  model: $m,
  measured_at: (now | todate),
  write_call: $w[0],
  read_call:  $r[0]
}' > results.json
echo "== wrote results.json =="
cat results.json
