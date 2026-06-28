#!/usr/bin/env bash
#
# Simulate an NFC tag scan against the local Done Manager backend.
# See architecture/api.md for the contract this hits.
#
# Usage:
#   DM_ACCESS_TOKEN=<plaintext-token> ./scan_tag.sh [external_id]
#
#   external_id   UUID written on the tag. Omit to generate a fresh one
#                 (first scan registers it; the response tells you to assign it).
#
# Env:
#   DM_ACCESS_TOKEN   Access token (required). Put it in test/.envrc.secrets or
#                   export it in the shell. Mint one in iex -S mix:
#                   {:ok, _t, plaintext} = DoneManager.Integrations.create_token(scope)
#   DM_BASE_URL       Backend base URL (default: http://localhost:4000)

set -euo pipefail

base_url="http://localhost:4000"
access_token="${DM_ACCESS_TOKEN}"

if [[ -z "$access_token" ]]; then
  echo "error: DM_ACCESS_TOKEN is not set. Run direnv allow in test/ or export it manually." >&2
  exit 1
fi

# external_id from the first arg, or generate a UUID.
external_id="33a68d6e-cc99-40ff-b2eb-25d95bbfcc35"

echo "POST ${base_url}/v1/tags/${external_id}/scans" >&2

curl -sS -X POST \
  --data-urlencode "access_token=${access_token}" \
  -w '\n-> HTTP %{http_code}\n' \
  "${base_url}/v1/tags/${external_id}/scans"
