#!/usr/bin/env bash

set -o pipefail

API_URL="https://tu-api/endpoint"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [OPTIONS] <hosts_file>

Check the environment of a list of hosts and print those detected as PRD.

Arguments:
  hosts_file              File containing one hostname per line.

Options:
  -h, --help              Show this help message and exit.

Environment variables:
  API_TOKEN               API authentication token. Required.

Examples:
  export API_TOKEN='your_token'
  $(basename "$0") hosts.txt

  API_TOKEN='your_token' $(basename "$0") /path/to/hosts.txt
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
command -v jq >/dev/null 2>&1 || die "jq is required."

echo "Checking hosts. The following hosts were detected as PRD:"
echo

while IFS= read -r host || [[ -n "$host" ]]; do
    [[ -z "$host" ]] && continue

    response=$(curl -sf \
        -H "Authorization: Bearer ${API_TOKEN}" \
        "${API_URL}?hostname=${host}"
    )

    if [[ $? -ne 0 ]]; then
        echo "WARNING: Failed to query host: $host" >&2
        continue
    fi

    environment=$(jq -r '.environment // "UNKNOWN"' <<< "$response")

    if [[ "$environment" == "PRD" ]]; then
        echo "$host"
    fi
done < "$HOSTS_FILE"