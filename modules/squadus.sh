#!/bin/bash
# Squadus alert function
# usage:
# squadus_send "<message>"

squadus_send() {

    local msg="$1"

    if [ -z "$msg" ]; then
        log ERROR "squadus_send: message is required"
        return 1
    fi

    log INFO "Sending Squadus message: $msg"

    local squadus_creds

    if ! squadus_creds=$(vault_get_secret "$OPENBAO_SQUADUS"); then
        log ERROR "Failed to load Squadus credentials"
        return 2
    fi

    local SQUADUS_ROOM
    local SQUADUS_URL
    local SQUADUS_USER_ID
    local SQUADUS_AUTH_TOKEN
    SQUADUS_ROOM=$(jq -r '.data.room_id // .data.data.room_id' <<< "$squadus_creds")
    SQUADUS_URL=$(jq -r '.data.url // .data.data.url' <<< "$squadus_creds")
    SQUADUS_USER_ID=$(jq -r '.data.user_id // .data.data.user_id' <<< "$squadus_creds")
    SQUADUS_AUTH_TOKEN=$(jq -r '.data.auth_token // .data.data.auth_token' <<< "$squadus_creds")

    local payload
    payload=$(jq -n \
        --arg rid "$SQUADUS_ROOM" \
        --arg msg "$msg" \
        '{
        message: {
            rid: $rid,
            msg: $msg
        }
    }')

    local response
    response=$(curl -sS \
        -X POST "${SQUADUS_URL}/api/v1/chat.sendMessage" \
        -H "X-Auth-Token: ${SQUADUS_AUTH_TOKEN}" \
        -H "X-User-Id: ${SQUADUS_USER_ID}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w "\n%{http_code}"
    )

    local body
    body=$(printf '%s' "$response" | sed '$d')
    local code
    code=$(printf '%s' "$response" | tail -n1)
    
    if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        log INFO "Squadus message sent successfully"
        return 0
    fi

    log ERROR "Squadus API error: HTTP $code"
    log ERROR "$body"

    return 3
}