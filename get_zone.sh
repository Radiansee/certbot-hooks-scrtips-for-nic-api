#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# logs
. "$SCRIPT_DIR/modules/log.sh"
init_logger "get_zone"

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

log INFO "Refreshing tokens"

refresh_tokens

log INFO "Requesting zone records"

if ! curl -fsS --request GET \
    "$NIC_API_BASE/dns-master/services/$SERVICE/zones/$ZONE/records?token=$ACCESS_TOKEN"; then
    log ERROR "Failed to get zone: $SERVICE/$ZONE"
    exit 2
fi
