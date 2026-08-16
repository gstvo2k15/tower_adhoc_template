#!/usr/bin/env bash

set -o pipefail

API_URL="https://api-platform.cib.echonet/IV2-capsule/referential"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [OPTIONS] <hosts_file>

Check a list of hosts and print those detected as DEV.

Arguments:
  hosts_file              File containing one hostname per line.

Options:
  -h, --help              Show this help message and exit.

Environment variables:
  API_KEY                 API key used in the x-apikey header. Required.

Examples:
  export API_KEY='your_api_key'
  $(basename "$0") hosts.txt

  API_KEY='your_api_key' $(basename "$0") /path/to/hosts.txt
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

[[ -n "${API_KEY:-}" ]] || die "API_KEY is not set."
[[ -f "$HOSTS_FILE" ]] || die "Hosts file not found: $HOSTS_FILE"
[[ -r "$HOSTS_FILE" ]] || die "Hosts file is not readable: $HOSTS_FILE"

command -v curl >/dev/null 2>&1 || die "curl is required."
command -v grep >/dev/null 2>&1 || die "grep is required."
command -v cut >/dev/null 2>&1 || die "cut is required."
command -v head >/dev/null 2>&1 || die "head is required."

echo "=== Starting host environment check ==="
echo
echo "Detected DEV hosts:"
echo

found=0

while IFS= read -r host || [[ -n "$host" ]]; do
    host="${host%$'\r'}"
    [[ -z "$host" ]] && continue

    response=$(curl -sf \
        -H "x-apikey: ${API_KEY}" \
        --get \
        --data-urlencode "hostname=${host}" \
        "${API_URL}"
    )

    if [[ $? -ne 0 ]]; then
        echo "WARNING: Failed to query host: $host" >&2
        continue
    fi

    environment=$(printf '%s' "$response" \
        | grep -o '"environment"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -n 1 \
        | cut -d'"' -f4)

    if [[ "$environment" == "DEV" ]]; then
        echo "$host"
        found=1
    fi

done < "$HOSTS_FILE"

echo

if [[ $found -eq 0 ]]; then
    echo "No DEV hosts were detected."
else
    echo "DEV host check completed."
fi