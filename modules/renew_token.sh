#!/bin/bash

set -euo pipefail

refresh_tokens() {

  log INFO "Loading NIC credentials from OpenBao"

  openbao_login
  auth_token=$(vault_get_secret "$OPENBAO_PATH" | jq -r '.data.auth_token // .data.data.auth_token')
  refresh_token=$(vault_get_secret "$OPENBAO_PATH" | jq -r '.data.refresh_token // .data.data.refresh_token')

  local response

  response=$(
    curl -fsS \
      --location \
      --request POST \
      "${NIC_API_BASE}/oauth/token?grant_type=refresh_token&refresh_token=${refresh_token}" \
      --header "Content-Type: application/x-www-form-urlencoded" \
      --header "Authorization: Basic ${auth_token}"
  )

  if [[ -z "$response" || "$response" == "null" ]]; then
    log ERROR "NIC token refresh failed"
    return 1
  fi

  local new_refresh_token

  ACCESS_TOKEN=$(jq -r '.access_token' <<< "$response")
  new_refresh_token=$(jq -r '.refresh_token' <<< "$response")


  if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    log ERROR "Failed to get new access token"
    return 2
  fi

  if [[ -z "$new_refresh_token" || "$new_refresh_token" == "null" ]]; then
    log ERROR "Failed to get new refresh token"
    return 3
  fi

  log INFO "NIC tokens successfully refreshed"

  log INFO "Updating access and refresh token in OpenBao"

  vault_write_secret "$OPENBAO_PATH" "access_token" "$ACCESS_TOKEN"
  vault_write_secret "$OPENBAO_PATH" "refresh_token" "$new_refresh_token"
}