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

log INFO "Start auth-hook"
trap 'log INFO "Script finished"' EXIT

# Load tokens from file
if [[ -f "$TOKEN_FILE" ]]; then
  export $(grep -v '^#' "$TOKEN_FILE" | xargs)
  log INFO "Tokens loaded from $TOKEN_FILE"
else
  log ERROR "Token file not found: $TOKEN_FILE"
  exit 1
fi

# Refresh tokens
refresh_nic_tokens() {
  log INFO "Getting new tokens from NIC..."

  local response access_token refresh_token

  response=$(curl -s --location --request POST \
    "$NIC_API_BASE/oauth/token?grant_type=refresh_token&refresh_token=${NIC_REFRESH_TOKEN}" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --header "Authorization: Basic ${NIC_CLIENT_AUTH}")

  access_token=$(echo "$response" | jq -r .access_token)
  refresh_token=$(echo "$response" | jq -r .refresh_token)

  log INFO "Access token is: $access_token"

  if [[ -z "$access_token" || "$access_token" == "null" ]]; then
    log ERROR "Failed to get access_token"
    log ERROR "$response"
    return 2
  fi

  sed -i "s|^NIC_ACCESS_TOKEN=.*|NIC_ACCESS_TOKEN=$access_token|" "$TOKEN_FILE"
  log INFO "Updated NIC_ACCESS_TOKEN in $TOKEN_FILE"

  if [[ -n "$refresh_token" && "$refresh_token" != "null" ]]; then
    sed -i "s|^NIC_REFRESH_TOKEN=.*|NIC_REFRESH_TOKEN=$refresh_token|" "$TOKEN_FILE"
    log INFO "Updated NIC_REFRESH_TOKEN in $TOKEN_FILE"
  else
    log ERROR "New refresh_token not received, not updating file"
    log ERROR "$response"
    return 3
  fi

  export NIC_ACCESS_TOKEN="$access_token"
  return 0
}

# Add DNS record
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

  if [[ "$response" == *"<error>"* ]]; then
    log ERROR "Failed to add DNS record"
    log ERROR "$response"
    return 1
  fi

  log INFO "DNS record successfully added"
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

# Verify new DNS TXT record
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

# Main logic

# environment
DOMAIN="$CERTBOT_DOMAIN"
VALIDATION="$CERTBOT_VALIDATION"
FQDN="_acme-challenge.$DOMAIN"

# 1. Refresh tokens
if ! refresh_nic_tokens; then
  log ERROR "Token refresh failed"
  exit 2
fi

# 2. Add DNS Record
if ! add_dns_record "$DOMAIN" "$VALIDATION" "$ZONE" "$NIC_ACCESS_TOKEN"; then
  log ERROR "Failed to add DNS record"
  exit 3
fi

# 3. Upload zone
if ! commit_zone "$ZONE" "$NIC_ACCESS_TOKEN"; then
  log ERROR "Failed to commit zone"
  exit 4
fi

# 4. Verify new DNS TXT record
if ! verify_new_dns_txt_record "$FQDN" "$VALIDATION"; then
  exit 5
fi

# 5. Save record id
RECORD_ID_GET=$(curl --request GET "$NIC_API_BASE/dns-master/services/$SERVICE/zones/$ZONE/records?token=$NIC_ACCESS_TOKEN" | grep "$CERTBOT_VALIDATION" | sed -n 's/.*<rr id="\([^"]*\)".*/\1/p')

if [ -n "$RECORD_ID_GET" ]; then
sed -i "s|^RECORD_ID=.*|RECORD_ID=$RECORD_ID_GET|" .env
else
  echo "RECORD_ID не найден!"
fi

# 6. NGINX reload
systemctl reload nginx

exit 0
