#!/bin/bash

# Log function
# usage:
# init_logger "<log_name without .log>"
# log INFO "for debug"

init_logger() {
    local log_name="$1"
    local project_root

    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    LOG_DIR="$project_root/logs"
    LOG_FILE="$LOG_DIR/${log_name}.log"

    mkdir -p "$LOG_DIR"
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo "[$level] $message"
}