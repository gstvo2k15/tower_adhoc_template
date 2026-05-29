#!/usr/bin/env bash
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin"

AWX_SCRIPT="${PWD}/awx_prompt.sh"
SLEEP_SECONDS=60
DAY="$(date +%u)"

case "$DAY" in
    1) CALLS_FILE="${PWD}/templates/weblogic.list" ;;
    2) CALLS_FILE="${PWD}/templates/websphere.list" ;;
    3) CALLS_FILE="${PWD}/templates/jbosseap.list" ;;
    4) CALLS_FILE="${PWD}/templates/tomcat.list" ;;
    5) CALLS_FILE="${PWD}/templates/apache.list" ;;
    *) echo "Non scheduled templated today"; exit 0 ;;
esac

[[ -r "$CALLS_FILE" ]] || {
    echo "ERROR: Cannot read $CALLS_FILE"
    exit 1
}

while IFS='|' read -r REGION ENV PROJECT LABEL GROUP ZONE; do
    [[ -z "$REGION" ]] && continue

    # ------------------------------------------------------------
    # -g (instance group)
    # ------------------------------------------------------------
    [[ "$GROUP" != "none" ]] && GROUP_OPT="-g $GROUP" || GROUP_OPT="-g none"

    # ------------------------------------------------------------
    # -t (is_ETS) - true only for ETS rows, false otherwise
    # ------------------------------------------------------------
    if [[ "$ZONE" == "ETS" ]]; then
        ETS_OPT="-t true"
    else
        ETS_OPT="-t false"
    fi

    # ------------------------------------------------------------
    # *** Pass ZONE with -z (location_zone) ***
    # ------------------------------------------------------------
    cmd=(
        bash "$AWX_SCRIPT"
        -r "$REGION"
        -e "$ENV"
        -p "$PROJECT"
        -l "$LABEL"
        -u update
        $GROUP_OPT
        -d prod $ETS_OPT -z "$ZONE"
    )

    echo -e "\n=== Starting: ${cmd[*]}"
    "${cmd[@]}"
    rc=$?

    (( rc != 0 )) && echo -e "\n>>> ERROR: exit code $rc"

    sleep "$SLEEP_SECONDS"

done < "$CALLS_FILE"