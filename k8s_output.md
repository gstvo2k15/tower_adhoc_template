#!/usr/bin/env bash

set -uo pipefail

DATE="$(date +%Y%m%d_%H%M%S)"
OUT="${OUT:-k8s-reverse-${DATE}}"

mkdir -p "$OUT"/{cluster,inventory,workloads,network,storage,rbac,gitops/argocd,gitops/flux,helm,operators/dynatrace,observability/fluentd,observability,webhooks,crds,images,secrets-metadata,analysis}

k() {
    sudo -i kubectl "$@"
}

h() {
    sudo -i helm "$@"
}

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

safe_kubectl() {
    local outfile="$1"
    shift

    k "$@" > "$outfile" 2>"${outfile}.err" || true

    if [[ ! -s "${outfile}.err" ]]; then
        rm -f "${outfile}.err"
    fi
}

resource_exists() {
    k api-resources -o name 2>/dev/null | grep -qx "$1"
}

safe_kubectl "$OUT/cluster/version.txt" version
safe_kubectl "$OUT/cluster/cluster-info.txt" cluster-info
safe_kubectl "$OUT/cluster/nodes-wide.txt" get nodes -o wide
safe_kubectl "$OUT/cluster/nodes.yaml" get nodes -o yaml
safe_kubectl "$OUT/cluster/namespaces.yaml" get namespaces -o yaml

k config current-context \
    > "$OUT/cluster/current-context.txt" 2>/dev/null || true

k config view --minify \
    > "$OUT/cluster/kubeconfig-minified.yaml" 2>/dev/null || true

sed -i \
    -e '/client-certificate-data:/d' \
    -e '/client-key-data:/d' \
    -e '/certificate-authority-data:/d' \
    -e '/token:/d' \
    "$OUT/cluster/kubeconfig-minified.yaml" 2>/dev/null || true

safe_kubectl "$OUT/inventory/pods-wide.txt" \
    get pods -A -o wide

safe_kubectl "$OUT/inventory/controllers-wide.txt" \
    get deployment,statefulset,daemonset -A -o wide

safe_kubectl "$OUT/inventory/services.txt" \
    get svc -A -o wide

safe_kubectl "$OUT/inventory/ingress.txt" \
    get ingress -A -o wide

safe_kubectl "$OUT/inventory/configmaps.txt" \
    get configmaps -A

safe_kubectl "$OUT/inventory/serviceaccounts.txt" \
    get serviceaccounts -A

safe_kubectl "$OUT/inventory/pvc.txt" \
    get pvc -A

safe_kubectl "$OUT/inventory/events.txt" \
    get events -A --sort-by=.metadata.creationTimestamp

safe_kubectl "$OUT/workloads/deployments.yaml" \
    get deployments -A -o yaml

safe_kubectl "$OUT/workloads/statefulsets.yaml" \
    get statefulsets -A -o yaml

safe_kubectl "$OUT/workloads/daemonsets.yaml" \
    get daemonsets -A -o yaml

safe_kubectl "$OUT/workloads/replicasets.yaml" \
    get replicasets -A -o yaml

safe_kubectl "$OUT/workloads/jobs.yaml" \
    get jobs -A -o yaml

safe_kubectl "$OUT/workloads/cronjobs.yaml" \
    get cronjobs -A -o yaml

k get pods -A -o jsonpath='
{range .items[*]}
{.metadata.namespace}{"\t"}
{.metadata.name}{"\t"}
{range .spec.initContainers[*]}
{"init:"}{.name}{"\t"}{.image}{"\n"}
{end}
{range .spec.containers[*]}
{.name}{"\t"}{.image}{"\n"}
{end}
{end}' \
    > "$OUT/images/pod-images.txt" 2>/dev/null || true

sort -u "$OUT/images/pod-images.txt" \
    > "$OUT/images/pod-images-unique.txt"

if command -v jq >/dev/null 2>&1; then

    k get pods -A -o json 2>/dev/null |
    jq -r '
      .items[] |
      .metadata.namespace as $ns |
      .metadata.name as $name |
      if (.metadata.ownerReferences | length) > 0 then
        .metadata.ownerReferences[] |
        [
          $ns,
          "Pod",
          $name,
          .kind,
          .name
        ] | @tsv
      else
        [
          $ns,
          "Pod",
          $name,
          "-",
          "-"
        ] | @tsv
      end
    ' > "$OUT/analysis/pod-owner-references.tsv"

    k get replicasets -A -o json 2>/dev/null |
    jq -r '
      .items[] |
      .metadata.namespace as $ns |
      .metadata.name as $name |
      if (.metadata.ownerReferences | length) > 0 then
        .metadata.ownerReferences[] |
        [
          $ns,
          "ReplicaSet",
          $name,
          .kind,
          .name
        ] | @tsv
      else empty end
    ' > "$OUT/analysis/replicaset-owner-references.tsv"

    for RESOURCE in deployments daemonsets statefulsets; do

        k get "$RESOURCE" -A -o json 2>/dev/null |
        jq -r '
          .items[] |
          .metadata.namespace as $ns |
          .metadata.name as $name |
          .kind as $kind |
          (.metadata.managedFields // [])[] |
          [
            $ns,
            $kind,
            $name,
            (.manager // "-"),
            (.operation // "-"),
            (.time // "-")
          ] |
          @tsv
        ' > "$OUT/analysis/${RESOURCE}-managed-fields.tsv"

    done

    k get deployments,daemonsets,statefulsets -A -o json 2>/dev/null |
    jq '
      .items[] |
      {
        namespace: .metadata.namespace,
        kind: .kind,
        name: .metadata.name,
        labels: .metadata.labels,
        annotations: .metadata.annotations
      }
    ' > "$OUT/analysis/workload-metadata.json"

fi

if sudo -i sh -c 'command -v helm' >/dev/null 2>&1; then

    h list -A \
        > "$OUT/helm/releases.txt" 2>"$OUT/helm/releases.err" || true

    h list -A -o json \
        > "$OUT/helm/releases.json" 2>/dev/null || true

    if command -v jq >/dev/null 2>&1; then

        while IFS=$'\t' read -r RELEASE NAMESPACE; do

            [[ -z "$RELEASE" ]] && continue

            DIR="$OUT/helm/${NAMESPACE}__${RELEASE}"

            mkdir -p "$DIR"

            log "Helm: $NAMESPACE/$RELEASE"

            h get values "$RELEASE" \
                -n "$NAMESPACE" \
                > "$DIR/values-user.yaml" 2>/dev/null || true

            h get values "$RELEASE" \
                -n "$NAMESPACE" \
                --all \
                > "$DIR/values-all.yaml" 2>/dev/null || true

            h get manifest "$RELEASE" \
                -n "$NAMESPACE" \
                > "$DIR/manifest.yaml" 2>/dev/null || true

            h history "$RELEASE" \
                -n "$NAMESPACE" \
                > "$DIR/history.txt" 2>/dev/null || true

        done < <(
            jq -r '.[] | [.name,.namespace] | @tsv' \
                "$OUT/helm/releases.json" 2>/dev/null
        )

    fi

fi

if resource_exists "applications.argoproj.io"; then

    safe_kubectl "$OUT/gitops/argocd/applications.yaml" \
        get applications.argoproj.io -A -o yaml

    if command -v jq >/dev/null 2>&1; then

        k get applications.argoproj.io -A -o json 2>/dev/null |
        jq -r '
          .items[] |
          [
            .metadata.namespace,
            .metadata.name,
            (.spec.source.repoURL // "-"),
            (.spec.source.targetRevision // "-"),
            (.spec.source.path // "-"),
            (.spec.source.chart // "-")
          ] |
          @tsv
        ' > "$OUT/gitops/argocd/sources.tsv"

    fi

fi

if resource_exists "applicationsets.argoproj.io"; then

    safe_kubectl "$OUT/gitops/argocd/applicationsets.yaml" \
        get applicationsets.argoproj.io -A -o yaml

fi

FLUX_RESOURCES=(
    "gitrepositories.source.toolkit.fluxcd.io"
    "helmrepositories.source.toolkit.fluxcd.io"
    "ocirepositories.source.toolkit.fluxcd.io"
    "kustomizations.kustomize.toolkit.fluxcd.io"
    "helmreleases.helm.toolkit.fluxcd.io"
)

for RESOURCE in "${FLUX_RESOURCES[@]}"; do

    if resource_exists "$RESOURCE"; then

        SHORT="${RESOURCE//./_}"

        safe_kubectl "$OUT/gitops/flux/${SHORT}.yaml" \
            get "$RESOURCE" -A -o yaml

    fi

done

safe_kubectl "$OUT/crds/crds.txt" \
    get crd

safe_kubectl "$OUT/crds/crds.yaml" \
    get crd -o yaml

grep -Ei \
'dynatrace|argoproj|flux|cert-manager|external-secret|kyverno|aqua|prometheus|grafana' \
"$OUT/crds/crds.txt" \
> "$OUT/crds/interesting-crds.txt" || true

if resource_exists "dynakubes.dynatrace.com"; then

    safe_kubectl "$OUT/operators/dynatrace/dynakubes.yaml" \
        get dynakubes.dynatrace.com -A -o yaml

fi

k get deployment,daemonset,statefulset,service \
    -n reserved-dynatrace -o yaml \
    > "$OUT/operators/dynatrace/resources.yaml" \
    2>/dev/null || true

if k get namespace fluentd >/dev/null 2>&1; then

    safe_kubectl "$OUT/observability/fluentd/daemonsets.yaml" \
        get daemonsets -n fluentd -o yaml

    safe_kubectl "$OUT/observability/fluentd/pods.yaml" \
        get pods -n fluentd -o yaml

    safe_kubectl "$OUT/observability/fluentd/configmaps.yaml" \
        get configmaps -n fluentd -o yaml

    safe_kubectl "$OUT/observability/fluentd/services.yaml" \
        get services -n fluentd -o yaml

    safe_kubectl "$OUT/observability/fluentd/serviceaccounts.yaml" \
        get serviceaccounts -n fluentd -o yaml

fi

k get pods -A 2>/dev/null |
grep -Ei \
'prometheus|grafana|loki|alloy|alertmanager|fluent|elastic|opensearch|splunk|dynatrace|datadog|newrelic|jaeger|tempo|otel|opentelemetry|monitor' \
> "$OUT/observability/pods-detected.txt" || true

k get services -A 2>/dev/null |
grep -Ei \
'prometheus|grafana|loki|alloy|alertmanager|fluent|elastic|opensearch|splunk|dynatrace|datadog|newrelic|jaeger|tempo|otel|opentelemetry|monitor' \
> "$OUT/observability/services-detected.txt" || true

k get deployment,daemonset,statefulset -A 2>/dev/null |
grep -Ei \
'prometheus|grafana|loki|alloy|alertmanager|fluent|elastic|opensearch|splunk|dynatrace|datadog|newrelic|jaeger|tempo|otel|opentelemetry|monitor' \
> "$OUT/observability/workloads-detected.txt" || true

safe_kubectl "$OUT/webhooks/mutating.yaml" \
    get mutatingwebhookconfigurations -o yaml

safe_kubectl "$OUT/webhooks/validating.yaml" \
    get validatingwebhookconfigurations -o yaml

k get mutatingwebhookconfigurations 2>/dev/null |
grep -Ei \
'dynatrace|istio|linkerd|vault|kyverno|aqua|cert|monitor' \
> "$OUT/webhooks/interesting-mutating.txt" || true

safe_kubectl "$OUT/rbac/serviceaccounts.yaml" \
    get serviceaccounts -A -o yaml

safe_kubectl "$OUT/rbac/roles.yaml" \
    get roles -A -o yaml

safe_kubectl "$OUT/rbac/rolebindings.yaml" \
    get rolebindings -A -o yaml

safe_kubectl "$OUT/rbac/clusterroles.yaml" \
    get clusterroles -o yaml

safe_kubectl "$OUT/rbac/clusterrolebindings.yaml" \
    get clusterrolebindings -o yaml

safe_kubectl "$OUT/network/services.yaml" \
    get services -A -o yaml

safe_kubectl "$OUT/network/ingress.yaml" \
    get ingress -A -o yaml

safe_kubectl "$OUT/network/endpointslices.yaml" \
    get endpointslices -A -o yaml

safe_kubectl "$OUT/network/networkpolicies.yaml" \
    get networkpolicies -A -o yaml

safe_kubectl "$OUT/storage/storageclasses.yaml" \
    get storageclasses -o yaml

safe_kubectl "$OUT/storage/pv.yaml" \
    get pv -o yaml

safe_kubectl "$OUT/storage/pvc.yaml" \
    get pvc -A -o yaml

if command -v jq >/dev/null 2>&1; then

    k get secrets -A -o json 2>/dev/null |
    jq '
      .items[] |
      {
        namespace: .metadata.namespace,
        name: .metadata.name,
        type: .type,
        labels: .metadata.labels,
        annotations: .metadata.annotations,
        keys: ((.data // {}) | keys)
      }
    ' > "$OUT/secrets-metadata/secrets.json"

else

    safe_kubectl "$OUT/secrets-metadata/secrets.txt" \
        get secrets -A

fi

k get secrets -A 2>/dev/null |
grep 'sh.helm.release' \
> "$OUT/helm/helm-secret-revisions.txt" || true

{
    echo "KUBERNETES REVERSE ENGINEERING"
    echo "Generated: $(date)"
    echo
    echo "Context:"
    k config current-context 2>/dev/null || true
    echo
    echo "Nodes:"
    k get nodes --no-headers 2>/dev/null | wc -l
    echo
    echo "Namespaces:"
    k get ns --no-headers 2>/dev/null | wc -l
    echo
    echo "Pods:"
    k get pods -A --no-headers 2>/dev/null | wc -l
    echo
    echo "Deployments:"
    k get deployments -A --no-headers 2>/dev/null | wc -l
    echo
    echo "DaemonSets:"
    k get daemonsets -A --no-headers 2>/dev/null | wc -l
    echo
    echo "StatefulSets:"
    k get statefulsets -A --no-headers 2>/dev/null | wc -l
    echo
    echo "CRDs:"
    k get crd --no-headers 2>/dev/null | wc -l
    echo
    echo "Detected observability components:"
    cat "$OUT/observability/workloads-detected.txt" 2>/dev/null || true
} > "$OUT/SUMMARY.txt"

echo
echo "Resultado: $OUT"
echo "Resumen: $OUT/SUMMARY.txt"