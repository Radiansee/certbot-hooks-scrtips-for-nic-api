#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# logs
. "$SCRIPT_DIR/modules/log.sh"
init_logger "auth"

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
. "$SCRIPT_DIR/modules/renew_token.sh"

# get nic parameters
openbao_login

if ! NIC_ENV=$(vault_get_secret "$OPENBAO_PATH"); then
    log ERROR "Failed to load NIC.ru parameters from OpenBao"
    exit 1
fi

NIC_API_BASE=$(jq -r '.data.nic_api_base // .data.data.nic_api_base' <<< "$NIC_ENV")
SERVICE=$(jq -r '.data.service // .data.data.service' <<< "$NIC_ENV")
ZONE=$(jq -r '.data.zone // .data.data.zone' <<< "$NIC_ENV")

# =========================
# Add DNS record
# =========================
add_dns_record() {
  local domain="$1"
  local validation="$2"
  local zone="$3"
  local access_token="$4"

  local record_name="_acme-challenge.${domain%.$zone}"

  log INFO "Adding DNS record: $record_name -> $validation"

  local xml_payload="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<request>
  <rr-list>
    <rr>
      <name>${record_name}</name>
      <ttl>300</ttl>
      <type>TXT</type>
      <txt>
        <string>${validation}</string>
      </txt>
    </rr>
  </rr-list>
</request>"

  log INFO "Payload:"
  log INFO "$xml_payload"

  local url="$NIC_API_BASE/dns-master/services/$SERVICE/zones/$zone/records"

  local response
  response=$(curl -s -X PUT "$url" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/xml" \
    -d "$xml_payload")

  if [[ "$response" == *"<status>fail</status>"* ]]; then
    log ERROR "Failed to add DNS record"
    log ERROR "$response"
    return 1
  fi

  log INFO "DNS record successfully added"
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
# Verify new DNS TXT record
# =========================
verify_new_dns_txt_record() {
  local fqdn="$1"
  local expected_value="$2"

  log INFO "Verifying new DNS TXT record for $fqdn..."

  for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
    echo "Attempt $i of $MAX_ATTEMPTS..."

    if nslookup -type=txt "$fqdn" | grep -q "$expected_value"; then
        log INFO "DNS TXT record propagated!"
        return 0
    else
        log INFO "Record not yet available. Waiting $SLEEP_TIME seconds..."
        sleep "$SLEEP_TIME"
    fi
  done

  log ERROR "DNS TXT record not propagated after $((MAX_ATTEMPTS * SLEEP_TIME)) seconds."
  return 1
}

# =========================
# Main logic
# =========================

# environment
DOMAIN="$CERTBOT_DOMAIN"
VALIDATION="$CERTBOT_VALIDATION"
FQDN="_acme-challenge.$DOMAIN"

# 1. Refresh tokens
log INFO "Refreshing tokens"
if ! refresh_tokens; then
  log ERROR "Token refresh failed"
  squadus_send "Auth-hook error: Token refresh failed"
  exit 2
fi

# 2. Add DNS Record
if ! add_dns_record "$DOMAIN" "$VALIDATION" "$ZONE" "$ACCESS_TOKEN"; then
  log ERROR "Failed to add DNS record"
  squadus_send "Auth-hook error: Failed to add DNS record"
  exit 3
fi

# 3. Upload zone
if ! commit_zone "$ZONE" "$ACCESS_TOKEN"; then
  log ERROR "Failed to commit zone"
  squadus_send "Auth-hook error: Failed to commit zone"
  exit 4
fi

# 4. Verify new DNS TXT record
if ! verify_new_dns_txt_record "$FQDN" "$VALIDATION"; then
squadus_send "Auth-hook error: Failed to verify new dns txt record"
  exit 5
fi

# 5. Save record id
NEW_RECORD_ID=$(curl -s --request GET "$NIC_API_BASE/dns-master/services/$SERVICE/zones/$ZONE/records?token=$ACCESS_TOKEN" | grep "$VALIDATION" | sed -n 's/.*<rr id="\([^"]*\)".*/\1/p')

if [ -n "$NEW_RECORD_ID" ]; then
  echo "$NEW_RECORD_ID" >> "/tmp/certbot_${CERTBOT_DOMAIN}.records"
else
  log ERROR "RECORD_ID not found!"
  squadus_send "Auth-hook error: RECORD_ID not found"
fi

log INFO "Auth-hook successfully added validation dns record" 
exit 0