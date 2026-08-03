```bash
openshift-poc/
├── tomcat/
│   ├── Dockerfile
│   └── ROOT/
│       └── index.jsp
│
├── workflow/
│   ├── serviceaccount.yaml
│   ├── role.yaml
│   ├── rolebinding.yaml
│   └── build-tomcat.yaml
│
├── kustomize/
│   └── dev/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── route.yaml
│       └── kustomization.yaml
│
└── argocd/
    └── application-kustomize.yaml
```


El orden correcto para arrancar esta P$OC en OpenShift sería este:

    - Preparar los ficheros en Git bajo openshift-poc/.
    - Crear ServiceAccount + RBAC en middleware-poc.
    - Lanzar manualmente el Workflow desde Argo Workflows para construir la imagen y publicarla en Artifactory.
    - Comprobar que la imagen existe en Artifactory.
    - Crear la Application en Argo CD apuntando a openshift-poc/kustomize/dev.
    - Argo CD sincroniza y despliega en middleware-poc.

```bash
Git
 │
 ▼
ServiceAccount/RBAC
 │
 ▼
Argo Workflows
 │
 ▼
Artifactory
 │
 ▼
Argo CD
 │
 ▼
OpenShift
```


### Paso 1

Luego, en la consola web de OpenShift, proyecto:

middleware-poc

usas:

Import YAML

y creas primero estos tres recursos:

serviceaccount.yaml
role.yaml
rolebinding.yaml



### Paso 2

Después vas a Argo Workflows UI, eliges el namespace middleware-poc, haces:

Submit New Workflow
→ Edit using full workflow options
→ pegas build-tomcat.yaml
→ Submit

Ese Workflow debería hacer:

clone Bitbucket
→ build Dockerfile
→ push Artifactory


Cuando termine en Succeeded, vas a Artifactory y compruebas que existe:

middleware-docker-local-dev.artifactory.cib.echonet/
openshift-poc-tomcat:10.1.57-jdk11-debian13




### Paso 3

Solo entonces vas a Argo CD UI y creas la app con:

`openshift-poc/argocd/application-kustomize.yaml`

La Application apuntará a:

repo:
kube-cicd

branch:
feature/openshift-poc

path:
openshift-poc/kustomize/dev

namespace:
middleware-poc

Argo CD verá:
```bash
deployment.yaml
service.yaml
route.yaml
kustomization.yaml
```

y desplegará:

Deployment
Service
Route

en OpenShift.

El flujo de arranque real queda:

1. Git push
2. Crear SA/RBAC
3. Ejecutar Workflow
4. Ver imagen en Artifactory
5. Crear Application Argo CD
6. Sync
7. Ver Pod
8. Abrir Route





Necesitas un ServiceAccount dentro de middleware-p$OC con permisos para ejecutar el Workflow y, si usas Vault/BuildKit, con las asociaciones necesarias.

Primero mira si ya existe alguno adecuado desde la consola web de OpenShift:

Project: middleware-poc
→ User Management
→ ServiceAccounts

o según versión:

Workloads
→ ServiceAccounts

Busca nombres tipo:

argo
workflow
build
pipeline
default

Si tienes acceso a terminal web de OpenShift, también podrías consultar:
`$OC get serviceaccount -n middleware-poc`

Pero como no tienes oc, la UI es suficiente.

Para tu P$OC yo crearía uno propio:

openshift-poc-workflow

Y tu Workflow quedaría:

serviceAccountName: openshift-poc-workflow

Puedes crear el YAML en tu repo:

`openshift-poc/workflow/serviceaccount.yaml`

con:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openshift-poc-workflow
  namespace: middleware-poc
```

Después necesitas RBAC. Como mínimo, Argo Workflow necesita poder crear/gestionar sus recursos y pods. Un Role inicial:

```yaml
openshift-poc/workflow/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: openshift-poc-workflow
  namespace: middleware-poc

rules:
  - apiGroups:
      - argoproj.io
    resources:
      - workflows
      - workflowtaskresults
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch

  - apiGroups:
      - ""
    resources:
      - pods
      - pods/log
      - persistentvolumeclaims
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - patch
```
Y el binding:

`openshift-poc/workflow/rolebinding.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: openshift-poc-workflow
  namespace: middleware-poc

subjects:
  - kind: ServiceAccount
    name: openshift-poc-workflow
    namespace: middleware-poc

roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: openshift-poc-workflow

Luego el build-tomcat.yaml:

spec:
  serviceAccountName: openshift-poc-workflow

Ahora viene la parte importante: BuildKit con privileged: true probablemente no funcionará con un ServiceAccount normal en OpenShift. OpenShift aplica SCC.

Tu Workflow tiene:

securityContext:
  privileged: true
```
Eso requerirá normalmente que un administrador permita al ServiceAccount usar una SCC adecuada.

El admin podría hacer algo como:

```bash
$OC adm policy add-scc-to-user \
  privileged \
  -z openshift-poc-workflow \
  -n middleware-poc
```

Pero no recomiendo asumir que te van a dar privileged. En muchas empresas está prohibido.

La buena noticia es que vuestro Workflow anterior usaba:

`moby/buildkit:v0.9.3-rootless`

así que primero intentaría ejecutar BuildKit sin:

privileged: true

Por ejemplo:

```bash
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
```

Si BuildKit rootless funciona con vuestra configuración de OpenShift, es mucho mejor.

Hay otra dependencia: Vault. En Kubernetes shaun estaba ligado probablemente a:

`vault.hashicorp.com/role: "shaun"`

En OpenShift tu nuevo ServiceAccount:

`system:serviceaccount:middleware-poc:openshift-poc-workflow`

no tendrá automáticamente permisos para ese role de Vault.

Así que hay dos cosas distintas:

OpenShift ServiceAccount:
openshift-poc-workflow

Vault role:
shaun

No tienen por qué llamarse igual, pero Vault debe permitir que ese ServiceAccount se autentique contra el role configurado.

Idealmente crearíais un role Vault específico:

openshift-poc

y en el Workflow:

vault.hashicorp.com/role: "openshift-poc"

configurado para aceptar:

ServiceAccount:
openshift-poc-workflow

Namespace:
middleware-poc

Ese mapeo normalmente lo tiene que hacer el equipo que administra Vault.

Tu checklist queda:

1. Crear ServiceAccount:
   openshift-poc-workflow

2. Crear Role.

3. Crear RoleBinding.

4. Cambiar:
   serviceAccountName: openshift-poc-workflow

5. Confirmar que Argo Workflows puede usarlo.

6. Confirmar acceso a Vault.

7. Confirmar si BuildKit rootless funciona sin privileged.

8. Si no funciona, pedir SCC al equipo OpenShift.

Si usas la consola web, los tres YAML ServiceAccount + Role + RoleBinding los puedes crear desde:

Project middleware-poc
→ Import YAML




### LAST 12:30 AM 03/08:

Eso confirma que solo has creado la ServiceAccount; todavía no le has asociado ningún Role ni RoleBinding.

Los no son esperables:

create pods       no
create pods/log   no
create secrets    no
create pvc        no

No necesitas darle permiso para crear secretos. Los secretos se crean previamente. Para Argo Workflows necesitas principalmente permisos sobre workflowtaskresults; el controlador de Argo suele encargarse de crear los pods. Como tu Workflow usa volumeClaimTemplates, también necesitas comprobar cómo está configurado el controlador respecto a los PVC.

1. Crea workflow/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-workflow-poc
  namespace: middleware-poc

rules:
  # Permisos que necesita el executor moderno de Argo Workflows
  - apiGroups:
      - argoproj.io
    resources:
      - workflowtaskresults
    verbs:
      - create
      - patch

  # Lectura básica para diagnóstico
  - apiGroups:
      - ""
    resources:
      - pods
      - pods/log
    verbs:
      - get
      - list
      - watch

  # El Workflow usa volumeClaimTemplates
  - apiGroups:
      - ""
    resources:
      - persistentvolumeclaims
    verbs:
      - get
      - list
      - watch
      - create
      - delete
2. Crea workflow/rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-workflow-poc
  namespace: middleware-poc

subjects:
  - kind: ServiceAccount
    name: argo-workflow-poc
    namespace: middleware-poc

roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argo-workflow-poc
3. Aplica ambos

Desde openshift-poc:

$OC apply -f workflow/role.yaml
$OC apply -f workflow/rolebinding.yaml

Comprueba:

$OC get role,rolebinding -n middleware-p$OC | grep argo-workflow-poc



4. Verifica permisos relevantes
$OC auth can-i create workflowtaskresults.argoproj.io \
  --as=system:serviceaccount:middleware-poc:argo-workflow-p$OC \
  -n middleware-poc

Debe devolver:
yes


$OC auth can-i patch workflowtaskresults.argoproj.io \
  --as=system:serviceaccount:middleware-poc:argo-workflow-p$OC \
  -n middleware-poc

Debe devolver:
yes


$OC auth can-i get pods \
  --as=system:serviceaccount:middleware-poc:argo-workflow-p$OC \
  -n middleware-poc

$OC auth can-i get pods/log \
  --as=system:serviceaccount:middleware-poc:argo-workflow-p$OC \
  -n middleware-poc

$OC auth can-i create persistentvolumeclaims \
  --as=system:serviceaccount:middleware-poc:argo-workflow-p$OC \
  -n middleware-poc

No compruebes:

$OC auth can-i create pods/log

Los logs no se crean; se consultan con get.

5. Sintaxis correcta para comprobar la SCC

Tu comando falló porque restricted-v2 debe formar parte del recurso:

$OC auth can-i use \
  securitycontextconstraints.security.openshift.io/restricted-v2 \
  --as=system:serviceaccount:middleware-poc:argo-workflow-poc

También puedes probar:

$OC auth can-i use scc/restricted-v2 \
  --as=system:serviceaccount:middleware-poc:argo-workflow-poc

Debería devolver:
yes

Pero el hecho de poder usar restricted-v2 no significa que tu Workflow actual vaya a arrancar. En el build-tomcat.yaml tienes:

```yaml
securityContext:
  privileged: true
```
Eso es incompatible con restricted-v2.

6. Cambia BuildKit para la primera prueba

Como usas una imagen BuildKit rootless:

image: "{{workflow.parameters.docker-repo}}/moby/buildkit:v0.9.3-rootless"

elimina:

securityContext:
  privileged: true

y usa:

securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL

Si la imagen requiere escribir en el filesystem raíz, también puede fallar bajo restricted-v2; primero prueba sin readOnlyRootFilesystem.

7. No añadas permiso para crear secretos

Este resultado puede seguir siendo:

create secrets: no

Es correcto. Crea previamente los secretos necesarios con tu usuario:

credenciales Bitbucket
credenciales Artifactory
pull secret

El Workflow solo debería leerlos mediante secretKeyRef o recibirlos mediante Vault.

8. Comprueba que Argo Workflows existe

Antes de lanzar build-tomcat.yaml:

$OC api-resources | grep -i workflow
$OC get crd workflows.argoproj.io
$OC get workflows -A

Si aparece:

the server doesn't have a resource type "workflows"

Argo Workflows no está instalado en ese OpenShift.

También localiza el namespace:

$OC get pods -A | grep -Ei 'workflow-controller|argo-server'
Estado actual
ServiceAccount: creada
Role: falta aplicar
RoleBinding: falta aplicar
SCC restricted-v2: comprobar con sintaxis correcta
BuildKit privileged: debe eliminarse
Argo Workflows instalado: falta comprobar
Credenciales Bitbucket/Artifactory: falta resolver

El siguiente paso inmediato es:

$OC apply -f workflow/role.yaml
$OC apply -f workflow/rolebinding.yaml
$OC get crd workflows.argoproj.io


### LAST 1402h

Ese 403 significa que tu usuario no puede crear Role en middleware-poc. Puedes crear algunos recursos namespaced, como el ServiceAccount, pero no conceder permisos RBAC.

No sigas intentando ampliar permisos desde tu usuario.

Comprueba exactamente qué puedes crear:

$OC auth can-i create roles.rbac.authorization.k8s.io \
  -n middleware-poc
$OC auth can-i create rolebindings.rbac.authorization.k8s.io \
  -n middleware-poc

Devolverán previsiblemente:

no
Qué debe hacer un administrador

Entrégale estos tres datos:

Namespace:
middleware-poc

ServiceAccount:
argo-workflow-poc

Identidad completa:
system:serviceaccount:middleware-poc:argo-workflow-poc

Y estos manifiestos.

workflow/role.yaml
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-workflow-poc
  namespace: middleware-poc
rules:
  - apiGroups:
      - argoproj.io
    resources:
      - workflowtaskresults
    verbs:
      - create
      - patch

  - apiGroups:
      - ""
    resources:
      - pods
      - pods/log
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - ""
    resources:
      - persistentvolumeclaims
    verbs:
      - get
      - list
      - watch
      - create
      - delete
workflow/rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-workflow-poc
  namespace: middleware-poc
subjects:
  - kind: ServiceAccount
    name: argo-workflow-poc
    namespace: middleware-poc
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argo-workflow-poc
```

El administrador ejecutaría:

$OC apply -f workflow/role.yaml
$OC apply -f workflow/rolebinding.yaml
Posible alternativa ya existente

Antes de pedir RBAC nuevo, comprueba si el equipo de OpenShift ya proporciona una ServiceAccount para Argo Workflows:

$OC get serviceaccounts -A | grep -Ei 'argo|workflow|pipeline'

Y localiza Argo Workflows:

$OC get pods -A | grep -Ei 'workflow-controller|argo-server'

Puede existir una SA autorizada en otro namespace, pero no podrás usarla directamente en middleware-poc: las ServiceAccounts son namespaced.

No uses builder

builder tiene permisos relacionados con BuildConfig y Builds de OpenShift, visibles en tu salida:

builds/docker
builds/source
buildconfigs/webhooks

Eso no equivale a permisos para Argo Workflows ni BuildKit.

Bloqueo actual

El proyecto está bloqueado en infraestructura:

ServiceAccount creada             sí
Role                               no, 403
RoleBinding                        no
Workflow ejecutable               todavía no
Imagen en Artifactory             todavía no
Argo CD                            no debe sincronizar aún

Necesitas que el responsable de OpenShift aplique el RBAC o te asigne un rol autorizado ya existente. El 403 no se arregla modificando el Workflow.

