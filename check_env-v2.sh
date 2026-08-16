#!/usr/bin/env bash

set -o pipefail

API_URL="https://api-platform.cib.echonet/IV2-capsule/referential"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [OPTIONS] <hosts_file>

Check a list of hosts and print those detected as PRD.

Arguments:
  hosts_file              File containing one hostname per line.

Options:
  -h, --help              Show this help message and exit.

Environment variables:
  API_TOKEN               API authentication token. Required.

Examples:
  export API_TOKEN='your_token'
  $(basename "$0") hosts.txt
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

[[ $# -eq 1 ]] || {
    usage >&2
    exit 1
}

HOSTS_FILE="$1"

[[ -n "${API_TOKEN:-}" ]] || die "API_TOKEN is not set."
[[ -f "$HOSTS_FILE" ]] || die "Hosts file not found: $HOSTS_FILE"
[[ -r "$HOSTS_FILE" ]] || die "Hosts file is not readable: $HOSTS_FILE"

command -v curl >/dev/null 2>&1 || die "curl is required."
command -v sed >/dev/null 2>&1 || die "sed is required."

echo "Hosts detected as PRD:"
echo

while IFS= read -r host || [[ -n "$host" ]]; do
    host="${host%$'\r'}"
    [[ -z "$host" ]] && continue

    response=$(curl -sf \
        -H "Authorization: Bearer ${API_TOKEN}" \
        --get \
        --data-urlencode "hostname=${host}" \
        "$API_URL"
    )

    if [[ $? -ne 0 ]]; then
        echo "WARNING: Failed to query host: $host" >&2
        continue
    fi

    environment=$(printf '%s' "$response" \
        | sed -n 's/.*"environment"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1)

    if [[ "$environment" == "PRD" ]]; then
        echo "$host"
    fi

done < "$HOSTS_FILE"