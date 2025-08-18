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

curl --request GET "$NIC_API_BASE/dns-master/services/$SERVICE/zones/$ZONE/records?token=$NIC_ACCESS_TOKEN"