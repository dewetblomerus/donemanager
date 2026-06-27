#!/usr/bin/env bash
#
# Simulate an NFC tag scan against the local Done Manager backend.
# See architecture/api.md for the contract this hits.
#
# Usage:
#   DM_TOKEN=<plaintext-token> ./scan_tag.sh [external_id]
#
#   external_id   UUID written on the tag. Omit to generate a fresh one
#                 (first scan registers it; the response tells you to assign it).
#
# Env:
#   DM_TOKEN      Bearer token (required). Mint one in iex -S mix:
#                   {:ok, _t, plaintext} = DoneManager.Integrations.create_token(scope)
#   DM_BASE_URL   Backend base URL (default: http://localhost:4000)

set -euo pipefail

base_url="${DM_BASE_URL:-http://localhost:4000}"
token="${DM_TOKEN:-b2l3zRkF.-ud_WHtJRjvi3S2Ia6aJc_gmu3J8XjvY}"

if [[ -z "$token" ]]; then
  echo "error: set DM_TOKEN to a bearer token. See README.md." >&2
  exit 1
fi

# external_id from the first arg, or generate a UUID.
external_id="a5421a61-0ae9-4c49-b7bc-239652f7f94b"

echo "POST ${base_url}/v1/tags/${external_id}/scans" >&2

curl -sS -X POST \
  -H "Authorization: Bearer ${token}" \
  -w '\n-> HTTP %{http_code}\n' \
  "${base_url}/v1/tags/${external_id}/scans"
