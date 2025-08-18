#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Load constants from env file
set -o allexport
source .env
set +o allexport

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo "[$level] $message"
}

log INFO "Start cleanup-hook"
trap 'log INFO "Script finished"' EXIT

# Load tokens from file
if [[ -f "$TOKEN_FILE" ]]; then
  export $(grep -v '^#' "$TOKEN_FILE" | xargs)
  log INFO "Tokens loaded from $TOKEN_FILE"
else
  log ERROR "Token file not found: $TOKEN_FILE"
  exit 1
fi

# Delete DNS record
delete_dns_record() {
  local zone="$1"
  local access_token="$2"
  local record_id="$3"

  log INFO "Deleting DNS record with ID: $record_id"

  local url="$NIC_API_BASE/dns-master/services/$SERVICE/zones/$zone/records/$record_id"

  local response
  response=$(curl -s -X DELETE "$url" -H "Authorization: Bearer $access_token")

  if [[ "$response" == *"<error>"* ]]; then
    log ERROR "Failed to delete DNS record"
    log ERROR "$response"
    return 1
  fi

  log INFO "DNS record successfully deleted"
  return 0
}

# Upload zone
commit_zone() {
  local zone="$1"
  local access_token="$2"

  log INFO "Uploading zone changes for $zone..."

  local response
  response=$(curl -s --location --request POST "$NIC_API_BASE/dns-master/services/$SERVICE/zones/$zone/commit" \
    --header "Authorization: Bearer $access_token")

  if [[ "$response" == *"<error>"* ]]; then
    log ERROR "Failed to commit zone"
    log ERROR "$response"
    return 1
  fi

  log INFO "Zone committed successfully"
  return 0
}

# Main logic

# 1. Delete DNS Record
if ! delete_dns_record "$ZONE" "$NIC_ACCESS_TOKEN" "$RECORD_ID"; then
  log ERROR "Failed to add DNS record"
  exit 2
fi

# 2. Upload zone
if ! commit_zone "$ZONE" "$NIC_ACCESS_TOKEN"; then
  log ERROR "Failed to commit zone"
  exit 3
fi

exit 0
