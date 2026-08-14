#!/bin/bash
set -euo pipefail

BASE_DIR="/apps/mdw-reporting/dpi_reports/bitbucket_repos/elastic_inventory/schedule_awx"
AWX_PROMPT="${BASE_DIR}/awx_prompt.sh"

if (( $# != 2 )); then
    echo "Usage: $0 <application> <scope_region>" >&2
    echo >&2
    echo "Examples:" >&2
    echo "  $0 apache nonprd_amer" >&2
    echo "  $0 apache prd_amer" >&2
    echo "  $0 apache nonprd_emea" >&2
    echo "  $0 apache prd_emea" >&2
    echo "  $0 apache nonprd_apac" >&2
    echo "  $0 apache prd_apac" >&2
    exit 1
fi

APP="${1,,}"
SCOPE_REGION="${2,,}"

cd "$BASE_DIR" || exit 1


run_awx() {
    local region="$1"
    local env="$2"
    local project="$3"
    local inventory="$4"
    local group="$5"
    local zone="$6"

    echo
    echo "=== ${project} | ${region} | ${env} | ${zone} ==="

    bash "$AWX_PROMPT" \
        -r "$region" \
        -e "$env" \
        -p "$project" \
        -l "$inventory" \
        -u update \
        -g "$group" \
        -d prod \
        -t false \
        -z "$zone"
}


case "${APP}:${SCOPE_REGION}" in

    ####################################################################
    # APACHE - NONPRD - AMER
    ####################################################################
    apache:nonprd_amer)

        echo
        echo "=== Starting Apache NONPRD AMER ==="

        echo
        echo "=== apache_dmzi ==="

        run_awx \
            AMER \
            STG \
            apache_dmzi \
            apache_dmzi_amer_stg_dmzi \
            iv2amer \
            DMZI

        sleep 5


        echo
        echo "=== apache_dmzi_amer ==="

        run_awx \
            AMER \
            STG \
            apache_dmzi_amer \
            apache_dmzi_amer_amer_stg_dmzi \
            iv2amer \
            DMZI

        sleep 5


        echo
        echo "=== apache ==="

        run_awx \
            AMER \
            DEV \
            apache \
            apache_amer_dev_core \
            iv2amer \
            CORE

        run_awx \
            AMER \
            STG \
            apache \
            apache_amer_stg_core \
            iv2amer \
            CORE

        sleep 5


        echo
        echo "=== dpi_upgraded_apache ==="

        run_awx \
            AMER \
            DEV \
            dpi_upgraded_apache \
            dpi_upgraded_apache_amer_dev_core \
            iv2amer \
            CORE

        run_awx \
            AMER \
            STG \
            dpi_upgraded_apache \
            dpi_upgraded_apache_amer_stg_core \
            iv2amer \
            CORE

        sleep 5


        echo
        echo "=== sso_as_a_service ==="

        run_awx \
            AMER \
            DEV \
            sso_as_a_service \
            sso_as_a_service_amer_dev_core \
            iv2amer \
            CORE

        run_awx \
            AMER \
            STG \
            sso_as_a_service \
            sso_as_a_service_amer_stg_core \
            iv2amer \
            CORE
        ;;


    ####################################################################
    # APACHE - PRD - AMER
    ####################################################################
    apache:prd_amer)

        echo
        echo "=== Starting Apache PRD AMER ==="

        echo
        echo "=== apache_dmzi ==="

        run_awx \
            AMER \
            PRD \
            apache_dmzi \
            apache_dmzi_amer_stg_dmzi \
            iv2amer \
            DMZI

        sleep 5


        echo
        echo "=== apache_dmzi_amer ==="

        run_awx \
            AMER \
            PRD \
            apache_dmzi_amer \
            apache_dmzi_amer_amer_prd_dmzi \
            iv2amer \
            DMZI

        sleep 5


        echo
        echo "=== apache ==="

        run_awx \
            AMER \
            PRD \
            apache \
            apache_amer_prd_core \
            iv2amer \
            CORE

        run_awx \
            AMER \
            PRD \
            apache \
            apache_amer_prd_ets \
            iv2amer \
            ETS

        sleep 5


        echo
        echo "=== dpi_upgraded_apache ==="

        run_awx \
            AMER \
            PRD \
            dpi_upgraded_apache \
            dpi_upgraded_apache_amer_prd_core \
            iv2amer \
            CORE

        sleep 5


        echo
        echo "=== sso_as_a_service ==="

        run_awx \
            AMER \
            PRD \
            sso_as_a_service \
            sso_as_a_service_amer_prd_core \
            iv2amer \
            CORE
        ;;


    ####################################################################
    # APACHE - NONPRD - EMEA
    ####################################################################
    apache:nonprd_emea)

        echo
        echo "=== Starting Apache NONPRD EMEA ==="

        #
        # Introducir aquí únicamente los launches DEV/STG
        # existentes actualmente para EMEA.
        #
        # Ejemplo de formato:
        #
        # run_awx \
        #     EMEA \
        #     DEV \
        #     apache \
        #     <inventory_real> \
        #     <group_real> \
        #     CORE
        #
        # run_awx \
        #     EMEA \
        #     STG \
        #     apache \
        #     <inventory_real> \
        #     <group_real> \
        #     CORE
        #

        echo "ERROR: Apache NONPRD EMEA not configured" >&2
        exit 1
        ;;


    ####################################################################
    # APACHE - PRD - EMEA
    ####################################################################
    apache:prd_emea)

        echo
        echo "=== Starting Apache PRD EMEA ==="

        #
        # Aquí solamente launches con:
        #
        #   -e PRD
        #
        # usando los projects/inventories/zones reales de EMEA.
        #

        echo "ERROR: Apache PRD EMEA not configured" >&2
        exit 1
        ;;


    ####################################################################
    # APACHE - NONPRD - APAC
    ####################################################################
    apache:nonprd_apac)

        echo
        echo "=== Starting Apache NONPRD APAC ==="

        #
        # Introducir aquí únicamente los launches DEV/STG
        # existentes actualmente para APAC.
        #

        echo "ERROR: Apache NONPRD APAC not configured" >&2
        exit 1
        ;;


    ####################################################################
    # APACHE - PRD - APAC
    ####################################################################
    apache:prd_apac)

        echo
        echo "=== Starting Apache PRD APAC ==="

        #
        # Aquí solamente launches con:
        #
        #   -e PRD
        #
        # usando los projects/inventories/zones reales de APAC.
        #

        echo "ERROR: Apache PRD APAC not configured" >&2
        exit 1
        ;;


    ####################################################################
    # INVALID
    ####################################################################
    *)
        echo "ERROR: Unsupported launch: ${APP} ${SCOPE_REGION}" >&2
        echo >&2
        echo "Valid Apache launches:" >&2
        echo "  apache nonprd_amer" >&2
        echo "  apache prd_amer" >&2
        echo "  apache nonprd_emea" >&2
        echo "  apache prd_emea" >&2
        echo "  apache nonprd_apac" >&2
        echo "  apache prd_apac" >&2
        exit 1
        ;;
esac