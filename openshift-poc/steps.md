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


El orden correcto para arrancar esta POC en OpenShift sería este:

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





Necesitas un ServiceAccount dentro de middleware-poc con permisos para ejecutar el Workflow y, si usas Vault/BuildKit, con las asociaciones necesarias.

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
`oc get serviceaccount -n middleware-poc`

Pero como no tienes oc, la UI es suficiente.

Para tu POC yo crearía uno propio:

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
oc adm policy add-scc-to-user \
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