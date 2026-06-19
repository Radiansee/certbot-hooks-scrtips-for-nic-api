#!/bin/bash

openbao_login() {
  local payload

  payload=$(
    jq -n \
      --arg role_id "$OPENBAO_ROLE_ID" \
      --arg secret_id "$OPENBAO_SECRET_ID" \
      '{role_id:$role_id, secret_id:$secret_id}'
  )

  OPENBAO_TOKEN=$(
    curl -fsS \
      --request POST \
      --header "Content-Type: application/json" \
      --data "$payload" \
      "${VAULT_ADDR}/v1/auth/approle/login" \
    | jq -r '.auth.client_token'
  )

  if [[ -z "$OPENBAO_TOKEN" || "$OPENBAO_TOKEN" == "null" ]]; then
    log ERROR "Failed to get OpenBao token"
    return 1
  fi

  export OPENBAO_TOKEN
}

vault_get_secret() {
  local path="$1"

  local secret
  secret=$(
    curl -fsS \
      --request GET \
      --header "X-Vault-Token: $OPENBAO_TOKEN" \
      "${VAULT_ADDR}/v1/${path}"
  )

  if [[ -z "$secret" || "$secret" == "null" ]]; then
    log ERROR "Failed to get secret from path: $path"
    return 1
  fi
  
  echo "$secret"
}

vault_write_secret() {
  local path="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$path" || -z "$key" ]]; then
      log ERROR "vault_write_secret: path and key are required"
      return 1
  fi

  local current_secret
  if ! current_secret=$(vault_get_secret "$path" | jq -r '.data'); then
      log ERROR "Failed to read existing secret: $path"
      return 2
  fi

  local payload
  payload=$(
    jq -n \
    --arg key "$key" \
    --arg value "$value" \
    --argjson current "$current_secret" \
    '$current + {($key): $value}'
  )

  if ! curl -fsS \
      --request POST \
      --header "X-Vault-Token: $OPENBAO_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$payload" \
      "${VAULT_ADDR}/v1/${path}" \
      > /dev/null; then

      log ERROR "Failed to write secret: $path"
      return 3
  fi

  log INFO "Secret updated: $path ($key)"

  return 0
  }
