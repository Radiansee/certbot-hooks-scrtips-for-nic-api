#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# logs
. "$SCRIPT_DIR/modules/log.sh"
init_logger "cleanup"

# Load env
set -o allexport
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    . "$SCRIPT_DIR/.env"
else
    log INFO "Notice: .env file not found, skipping"
fi
set +o allexport

# include modules
. "$SCRIPT_DIR/modules/openbao.sh"
. "$SCRIPT_DIR/modules/squadus.sh"

# get nic parameters
openbao_login

if ! NIC_ENV=$(vault_get_secret "$OPENBAO_PATH"); then
    log ERROR "Failed to load NIC.ru parameters from OpenBao"
    exit 1
fi

NIC_API_BASE=$(jq -r '.data.nic_api_base // .data.data.nic_api_base' <<< "$NIC_ENV")
SERVICE=$(jq -r '.data.service // .data.data.service' <<< "$NIC_ENV")
ZONE=$(jq -r '.data.zone // .data.data.zone' <<< "$NIC_ENV")
ACCESS_TOKEN=$(jq -r '.data.access_token // .data.data.access_token' <<< "$NIC_ENV")

# =========================
# Delete DNS record
# =========================
delete_dns_record() {
  local zone="$1"
  local access_token="$2"
  local record_id="$3"

  log INFO "Deleting DNS record with ID: $record_id"

  local url="$NIC_API_BASE/dns-master/services/$SERVICE/zones/$zone/records/$record_id"

  local response
  response=$(curl -s -X DELETE "$url" -H "Authorization: Bearer $access_token")

  if [[ "$response" == *"<status>fail</status>"* ]]; then
    log ERROR "Failed to delete DNS record"
    log ERROR "$response"
    return 1
  fi

  log INFO "DNS record successfully deleted"
  return 0
}

# =========================
# Upload zone
# =========================
commit_zone() {
  local zone="$1"
  local access_token="$2"

  log INFO "Uploading zone changes for $zone..."

  local response
  response=$(curl -s --location --request POST "$NIC_API_BASE/dns-master/services/$SERVICE/zones/$zone/commit" \
    --header "Authorization: Bearer $access_token")

  if [[ "$response" == *"<status>fail</status>"* ]]; then
    log ERROR "Failed to commit zone"
    log ERROR "$response"
    return 1
  fi

  log INFO "Zone committed successfully"
  return 0
}

# =========================
# Main logic
# =========================
RECORDS_FILE="/tmp/certbot_${CERTBOT_DOMAIN}.records"

if [[ -f "$RECORDS_FILE" ]]; then
  while read -r RECORD_ID; do
    # skip empty lines
    [[ -z "$RECORD_ID" ]] && continue

# 1. Delete DNS Record
if ! delete_dns_record "$ZONE" "$ACCESS_TOKEN" "$RECORD_ID"; then
  log ERROR "Failed to delete DNS record $RECORD_ID"
  squadus_send "Cleanup-hook error: Failed to delete DNS record $RECORD_ID"
fi

  done < "$RECORDS_FILE"

  rm -f "$RECORDS_FILE"
fi

# 2. Upload zone
if ! commit_zone "$ZONE" "$ACCESS_TOKEN"; then
  log ERROR "Failed to commit zone"
  squadus_send "Cleanup-hook error: Failed to commit zone"
  exit 2
fi

exit 0