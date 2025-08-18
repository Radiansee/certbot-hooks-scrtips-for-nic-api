#!/bin/bash

set -euo pipefail

# Load constants from env file
set -o allexport
source .env
set +o allexport

if [[ -f "$TOKEN_FILE" ]]; then
  export $(grep -v '^#' "$TOKEN_FILE" | xargs)
else
  echo "[ERROR] Token file not found: $TOKEN_FILE"
  exit 1
fi

TOKEN_RESPONSE=$(curl -s --location --request POST \
  "${NIC_API_BASE}/oauth/token?grant_type=refresh_token&refresh_token=${NIC_REFRESH_TOKEN}" \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --header "Authorization: Basic ${NIC_CLIENT_AUTH}")

NEW_ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r .access_token)
NEW_REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r .refresh_token)

if [[ -z "$NEW_ACCESS_TOKEN" || "$NEW_ACCESS_TOKEN" == "null" ]]; then
  echo "[ERROR] Не удалось получить access_token"
  echo "$TOKEN_RESPONSE"
  exit 2
fi

echo "access:"
echo $NEW_ACCESS_TOKEN
echo "refresh:"
echo $NEW_REFRESH_TOKEN

sed -i "s|^NIC_REFRESH_TOKEN=.*|NIC_REFRESH_TOKEN=$NEW_REFRESH_TOKEN|" "$TOKEN_FILE"
sed -i "s|^NIC_ACCESS_TOKEN=.*|NIC_ACCESS_TOKEN=$NEW_ACCESS_TOKEN|" "$TOKEN_FILE"
