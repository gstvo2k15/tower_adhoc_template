En ~/.bashrc añade:

k() {
    sudo su - -c "kubectl $*"
}

Recarga:

source ~/.bashrc

Entonces:

k get pod -A

equivale a:

sudo su - -c "kubectl get pod -A"

También:

k get ns
k get deploy -A
k describe pod mi-pod -n apache
k get pod -n apache -o wide

Pero esa implementación tiene problemas con argumentos complejos, comillas y pipes. Es preferible:

k() {
    sudo -i kubectl "$@"
}

Entonces:

k get pod -A
k get deploy -n apache -o yaml
k logs -n apache tomcat-sample-kustomize-cicd-xxxxx

La alternativa más directa sería:

alias k='sudo -i kubectl'

en ~/.bashrc:

echo "alias k='sudo -i kubectl'" >> ~/.bashrc
source ~/.bashrc

Después:

k get pod -A
Si realmente necesitas su -

Si kubectl sólo funciona después de:

sudo su -

probablemente el motivo real es que el kubeconfig está sólo disponible para root, por ejemplo:

/root/.kube/config

Compruébalo:

sudo su - -c 'echo $KUBECONFIG; ls -la ~/.kube/'

y:

ls -la ~/.kube/

Es posible que actualmente tengas:

Usuario:
  /home/tuusuario/.kube/config   → inexistente

root:
  /root/.kube/config             → cluster config

La solución técnicamente más limpia no sería mantener sudo delante de kubectl, sino disponer del kubeconfig adecuado para tu usuario, siempre que las políticas de la empresa lo permitan:

tu usuario
    │
    ▼
~/.kube/config
    │
    ▼
kubectl
    │
    ▼
Kubernetes API

Así utilizarías directamente:

kubectl get pod -A

o el alias estándar:

alias k=kubectl

En un entorno corporativo no copiaría /root/.kube/config sin comprobar antes el modelo de acceso/RBAC establecido. Si root tiene credenciales de administración del clúster, copiar ese kubeconfig a tu usuario cambia materialmente el modelo de seguridad.

Para tu situación actual, la opción práctica y segura es:

alias k='sudo -i kubectl'

y utilizar:

k get pod -A





Sí. Kubernetes permite reconstruir bastante bien qué se desplegó, quién lo desplegó, con qué configuración y desde qué sistema GitOps/Helm vino.

La idea es recorrer la cadena inversa:

Pod
 │
 ▼
ReplicaSet / StatefulSet / DaemonSet
 │
 ▼
Deployment / CR / Helm Release
 │
 ▼
ArgoCD / Flux / Operator
 │
 ▼
Git / Helm chart / Kustomize

Para estudiar vuestro clúster lo haría de forma sistemática.

1. Partir de un Pod concreto

Por ejemplo tu Tomcat:

kubectl get pod -n apache \
  tomcat-sample-kustomize-cicd-85b9469f89-8hrf2 \
  -o yaml

No interesa leer todo de golpe. Primero:

kubectl get pod -n apache \
  tomcat-sample-kustomize-cicd-85b9469f89-8hrf2 \
  -o jsonpath='{.metadata.ownerReferences}'

Probablemente aparecerá:

ReplicaSet/tomcat-sample-kustomize-cicd-85b9469f89

Luego:

kubectl get rs -n apache \
  tomcat-sample-kustomize-cicd-85b9469f89 \
  -o jsonpath='{.metadata.ownerReferences}'

y llegarás a:

Deployment/tomcat-sample-kustomize-cicd

Finalmente:

kubectl get deployment -n apache \
  tomcat-sample-kustomize-cicd \
  -o yaml

Ese Deployment es mucho más interesante que el Pod.

2. Buscar señales de quién lo desplegó

Mira labels y annotations:

kubectl get deploy -n apache \
  tomcat-sample-kustomize-cicd \
  -o json | jq '{
    labels: .metadata.labels,
    annotations: .metadata.annotations
  }'

Busca cosas como:

app.kubernetes.io/managed-by: Helm

helm.sh/chart: ...
meta.helm.sh/release-name: ...
meta.helm.sh/release-namespace: ...

argocd.argoproj.io/instance: ...
argocd.argoproj.io/tracking-id: ...

kustomize.toolkit.fluxcd.io/name: ...
kustomize.toolkit.fluxcd.io/namespace: ...

helm.toolkit.fluxcd.io/name: ...

Eso suele revelar inmediatamente el origen.

Por ejemplo:

metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: tomcat

implica:

Helm Release
     │
     ▼
Deployment
     │
     ▼
ReplicaSet
     │
     ▼
Pods
3. managedFields: extremadamente útil

Kubernetes registra qué controlador modificó determinados campos.

kubectl get deploy -n apache \
  tomcat-sample-kustomize-cicd \
  -o json | jq '.metadata.managedFields[] |
  {
    manager,
    operation,
    apiVersion,
    time
  }'

Podrías obtener:

manager: argocd-controller
manager: kube-controller-manager
manager: kubectl-client-side-apply
manager: helm
manager: kustomize-controller
manager: dynatrace-webhook

Esto permite reconstruir quién ha tocado el recurso.

Un recurso podría haber tenido esta historia:

Kustomize
    │
    ▼
Argo CD
    │ crea
    ▼
Deployment
    │
    ├── Dynatrace webhook modifica
    │
    ▼
ReplicaSet
    │
    ▼
Pod

Es una de las cosas que más estudiaría.

4. Detectar Helm

Primero:

helm list -A

Esto podría mostrar:

NAME               NAMESPACE
dynatrace          reserved-dynatrace
fluentd            fluentd
cert-manager       reserved-cert-manager
...

Para una release:

helm get all dynatrace -n reserved-dynatrace

Este comando es particularmente potente.

Te devuelve:

chart
values
hooks
manifest
notes

También separadamente:

helm get values dynatrace -n reserved-dynatrace

Valores efectivos:

helm get values dynatrace -n reserved-dynatrace --all

Manifiestos:

helm get manifest dynatrace -n reserved-dynatrace

Historia:

helm history dynatrace -n reserved-dynatrace

Esto te permite reconstruir bastante fielmente el deployment.

5. Si no tienes acceso al comando Helm

Las releases Helm suelen quedar almacenadas como Secrets.

kubectl get secrets -A | grep 'sh.helm.release'

Verás algo parecido:

sh.helm.release.v1.dynatrace.v1
sh.helm.release.v1.dynatrace.v2
sh.helm.release.v1.dynatrace.v3

Eso ya te dice:

release: dynatrace
revision: 3

No modificaría esos Secrets. Son estado interno de Helm.

6. Argo CD

Como tenéis Argo CD, esto es prioritario:

kubectl get applications.argoproj.io -A

o:

kubectl get applications -n argo-cd

Después:

kubectl get application -n argo-cd <app> -o yaml

Busca:

spec:
  source:
    repoURL:
    targetRevision:
    path:

Por ejemplo:

spec:
  source:
    repoURL: ssh://git.example.com/platform/tomcat.git
    targetRevision: main
    path: environments/prod

Acabas de descubrir:

Git repository
      │
      ▼
environments/prod
      │
      ▼
Argo CD
      │
      ▼
Kubernetes

Si usa Helm mediante Argo:

source:
  repoURL: ...
  chart: tomcat
  targetRevision: 2.4.1

  helm:
    valueFiles:
      - values-prod.yaml

Si utiliza Kustomize:

source:
  path: overlays/prod

  kustomize:
    ...
7. Relacionar un Deployment con Argo CD

Prueba:

kubectl get deploy -n apache \
  tomcat-sample-kustomize-cicd \
  -o json | jq '.metadata.labels, .metadata.annotations'

Busca:

argocd.argoproj.io/instance

o:

argocd.argoproj.io/tracking-id

Después:

kubectl get applications -n argo-cd

Puedes reconstruir:

tomcat-sample-kustomize-cicd
          │
          ▼
Argo Application: tomcat-sample
          │
          ▼
repoURL
          │
          ▼
Git repo
          │
          ▼
overlays/prod

El nombre tomcat-sample-kustomize-cicd de vuestra aplicación ya sugiere fuertemente que existe Kustomize detrás, aunque el nombre por sí solo no lo demuestra.

8. Flux

En las capturas también aparece Flux.

Lista sus objetos:

kubectl get gitrepositories.source.toolkit.fluxcd.io -A
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A
kubectl get helmreleases.helm.toolkit.fluxcd.io -A
kubectl get helmrepositories.source.toolkit.fluxcd.io -A

Puedes abreviar normalmente:

kubectl get gitrepositories -A
kubectl get kustomizations -A
kubectl get helmreleases -A

Un GitRepository te puede mostrar:

spec:
  url: ssh://git@example.com/platform/kubernetes.git
  ref:
    branch: production

Una Kustomization:

spec:
  sourceRef:
    kind: GitRepository
    name: platform
  path: ./clusters/production

Entonces:

GitRepository
      │
      │ ./clusters/production
      ▼
Flux Kustomization
      │
      ▼
Resources Kubernetes
9. Operators y CRDs

Dynatrace es un buen ejemplo.

No empezaría mirando los DaemonSets de Dynatrace. Buscaría primero el recurso de alto nivel:

kubectl get dynakube -A

Después:

kubectl get dynakube -n reserved-dynatrace <nombre> -o yaml

Conceptualmente:

DynaKube CR
     │
     ▼
Dynatrace Operator
     │
     ├── DaemonSet OneAgent
     ├── StatefulSet ActiveGate
     ├── Services
     ├── Secrets
     └── demás objetos

El DynaKube contiene buena parte de la intención original.

Esto aplica a cualquier Operator.

Primero detecta CRDs:

kubectl get crd

Una forma útil:

kubectl get crd | sort

En vuestro caso buscaría:

kubectl get crd | egrep -i \
'dynatrace|argoproj|flux|cert-manager|external-secrets|kyverno|aquasec'
10. OwnerReferences

Puedes automatizar mentalmente esta regla:

objeto Kubernetes
       │
       ▼
metadata.ownerReferences
       │
       ▼
propietario

Por ejemplo:

kubectl get pod POD -n NS \
  -o json | jq '.metadata.ownerReferences'

Y vas ascendiendo.

Ejemplo real típico:

pod
 │
 ▼
ReplicaSet
 │
 ▼
Deployment

Para Operator:

Pod
 │
 ▼
DaemonSet
 │
 ▼
posiblemente Operator/CR

No siempre encontrarás toda la cadena mediante ownerReferences; algunos sistemas relacionan objetos mediante labels/annotations.

11. Investigar Fluentd

En vuestro caso:

kubectl get daemonset -n fluentd -o yaml

Especialmente:

kubectl get ds -n fluentd -o json | jq '.items[].spec.template.spec'

Mira:

image
command
args
env
volumeMounts
volumes
serviceAccountName

Luego:

kubectl get configmap -n fluentd

y:

kubectl get configmap -n fluentd -o yaml

Aquí probablemente encontrarás la configuración:

fluent.conf
kubernetes.conf
outputs.conf

Por ejemplo:

<source>
  @type tail
  path /var/log/containers/*.log
</source>

<match **>
  @type elasticsearch
  host elasticsearch.example
</match>

Eso te revelaría exactamente:

qué logs recoge
cómo los parsea
qué excluye
qué metadata añade
a dónde los envía

Para Fluentd la ingeniería inversa se centra mucho en:

DaemonSet
+
ConfigMaps
+
Secrets
+
variables de entorno

Evita imprimir Secrets directamente si pueden contener credenciales.

12. Descubrir configuración montada

Para cualquier Pod:

kubectl get pod POD -n NS -o json |
jq '.spec.volumes'

Puedes encontrar:

configMap:
  name: fluentd-config

o:

secret:
  secretName: dynatrace-token

Luego sigues la referencia:

Pod
 │
 ▼
Volume
 │
 ▼
ConfigMap fluentd-config
 │
 ▼
fluent.conf

Esto es ingeniería inversa Kubernetes pura.

13. Variables de entorno

Muy útiles:

kubectl get deploy DEPLOY -n NS -o json |
jq '.spec.template.spec.containers[] |
{
  name,
  image,
  env,
  envFrom
}'

Puedes encontrar:

envFrom:
  - configMapRef:
      name: application-config
  - secretRef:
      name: database-credentials

Continúas:

Deployment
 │
 ├── ConfigMap
 │
 └── Secret
14. Las imágenes contienen otra parte de la historia

Extrae todas:

kubectl get pods -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

O mejor:

kubectl get pods -A -o json |
jq -r '
.items[] |
.metadata.namespace as $ns |
.metadata.name as $pod |
.spec.containers[] |
[$ns,$pod,.name,.image] |
@tsv'

Esto revela:

registry corporativo
producto
versión
tag

Ejemplo:

registry.company.local/platform/fluentd:1.16.5-4

A partir de ahí sabes que existe probablemente:

Dockerfile
pipeline de build
repositorio de imágenes
versionado corporativo
15. Admission Webhooks: cambios posteriores al despliegue

Esto es importante con Dynatrace.

Lista:

kubectl get mutatingwebhookconfiguration
kubectl get validatingwebhookconfiguration

Por ejemplo:

kubectl get mutatingwebhookconfiguration \
  dynatrace-webhook \
  -o yaml

Un webhook puede hacer que el YAML de Git diga:

containers:
  - name: tomcat

pero que el Pod real tenga cosas adicionales.

Es decir:

Git manifest
      │
      ▼
API Server
      │
      ▼
Mutating webhook
      │
      + Dynatrace injection
      │
      ▼
Pod efectivo

Por eso el manifiesto live no necesariamente coincide exactamente con el manifiesto Git.

16. Comparar Deployment con Pod

Muy educativo:

kubectl get deploy -n apache tomcat-sample-kustomize-cicd -o yaml \
  > deployment.yaml

kubectl get pod -n apache tomcat-sample-kustomize-cicd-... -o yaml \
  > pod.yaml

Compara:

vimdiff deployment.yaml pod.yaml

o:

diff -u deployment.yaml pod.yaml

No serán directamente equivalentes estructuralmente, pero puedes buscar qué aparece en el Pod que no estaba en:

.spec.template

Especialmente:

initContainers
volumes
volumeMounts
env
annotations

Así puedes detectar inyección.

17. ServiceAccounts y RBAC

Para entender qué puede hacer un componente:

kubectl get pod POD -n NS \
  -o jsonpath='{.spec.serviceAccountName}'

Después:

kubectl get sa -n NS SERVICEACCOUNT -o yaml

Busca RoleBindings:

kubectl get rolebinding -n NS -o yaml |
grep -B5 -A10 SERVICEACCOUNT

Y ClusterRoleBindings:

kubectl get clusterrolebinding -o yaml |
grep -B5 -A10 SERVICEACCOUNT

También:

kubectl auth can-i --list \
  --as=system:serviceaccount:NS:SERVICEACCOUNT

Eso permite comprender:

Fluentd puede leer pods?
Dynatrace puede listar nodos?
Argo puede crear Deployments?
Operator puede gestionar CRDs?
18. Services, Ingress y tráfico

Para entender cómo entra tráfico:

kubectl get ingress -A
kubectl get svc -A

Para Tomcat:

kubectl get svc -n apache -o wide
kubectl get ingress -n apache -o yaml

Y endpoints:

kubectl get endpoints -n apache

o moderno:

kubectl get endpointslice -n apache

Reconstruyes:

Cliente
   │
   ▼
Load Balancer
   │
   ▼
Ingress nginx
   │
   ▼
Service
   │
   ▼
Tomcat Pods
19. Configuración externa

Para un namespace:

kubectl get all,cm,secret,ingress,pvc,sa -n apache

Eso proporciona un mapa inicial.

No recomiendo:

kubectl get secret -o yaml

indiscriminadamente.

Para investigar relaciones basta inicialmente:

kubectl get secret -n apache

y examinar referencias desde Deployments.

20. Comandos que usaría para mapear vuestro clúster

Primero inventario:

kubectl get ns
kubectl get deploy,ds,sts -A
kubectl get crd
helm list -A

GitOps:

kubectl get applications.argoproj.io -A
kubectl get gitrepositories.source.toolkit.fluxcd.io -A
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A
kubectl get helmreleases.helm.toolkit.fluxcd.io -A

Operators:

kubectl get dynakube -A

Configuración:

kubectl get cm -A

Webhooks:

kubectl get mutatingwebhookconfiguration
kubectl get validatingwebhookconfiguration

Storage:

kubectl get sc,pv,pvc -A

Networking:

kubectl get ingress,svc,endpointslice -A
21. Para cada componente, construir una ficha

Por ejemplo para Fluentd:

COMPONENTE: Fluentd

Namespace:
  fluentd

Workload:
  DaemonSet

Pods:
  6

Imagen:
  registry/.../fluentd:x.y

Configuración:
  ConfigMap fluentd-config

ServiceAccount:
  fluentd

Origen:
  Helm / Argo / Flux / manual

Logs entrada:
  /var/log/containers/*.log

Destino:
  ???

Owner:
  ???

Git repository:
  ???

Versión:
  ???

Para Dynatrace:

COMPONENTE: Dynatrace

Namespace:
  reserved-dynatrace

Entrada declarativa:
  DynaKube

Controlador:
  Dynatrace Operator

Node agent:
  OneAgent

Gateway:
  ActiveGate

Injection:
  Dynatrace webhook

Origen deployment:
  Helm / Flux / otro

Config:
  DynaKube spec

Credentials:
  Secrets (no extraer contenido)

Backend:
  URL/configuración Dynatrace

Así empiezas a comprender realmente la plataforma.

22. Hay tres estados diferentes que no debes confundir

Esto es lo esencial:

               SOURCE OF TRUTH
               Git / Helm values
                       │
                       ▼
                DESIRED STATE
           Deployment / DynaKube / etc.
                       │
                       ▼
             Controllers + Webhooks
                       │
                       ▼
                 LIVE STATE
                   Pods

Si sólo haces:

kubectl get pod -o yaml

estás viendo únicamente el último nivel.

La ingeniería inversa correcta consiste en ir:

LIVE STATE
    │
    ▼
Desired State
    │
    ▼
Controller
    │
    ▼
Helm / Argo / Flux
    │
    ▼
Git source

Hasta encontrar el source of truth.

Para vuestro clúster empezaría concretamente por estos cuatro:

helm list -A

kubectl get applications.argoproj.io -A

kubectl get helmreleases.helm.toolkit.fluxcd.io -A
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A

kubectl get dynakube -A

Con esas salidas probablemente se puede reconstruir una parte muy considerable de cómo está diseñada y desplegada vuestra plataforma.


```bash
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
```