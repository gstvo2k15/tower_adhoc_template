openshift-poc/
├── tomcat/
│   ├── Dockerfile
│   └── ROOT/
│       └── index.jsp
│
├── workflow/
│   ├── check-debian-java.yaml
│   └── build-tomcat.yaml
│
├── helm/
│   └── openshift-poc/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── route.yaml
│
├── kustomize/
│   ├── base/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   │
│   └── overlays/
│       └── dev/
│           ├── route.yaml
│           ├── patch-deployment.yaml
│           └── kustomization.yaml
│
└── argocd/
    ├── application-helm.yaml
    └── application-kustomize.yaml


La idea es que puedas probar ambos enfoques.

Para Helm:

Argo CD
  ↓
openshift-poc/helm/openshift-poc
  ↓
Deployment + Service + Route


Para Kustomize:

Argo CD
  ↓
openshift-poc/kustomize/overlays/dev
  ↓
base
+
parches dev
+
Route



No usaría Helm y Kustomize simultáneamente para gestionar el mismo Deployment en el mismo namespace, porque se pisarían. Los tienes ambos en el repo para aprender y comparar, pero eliges uno por Application.

# Kustomize base

openshift-poc/kustomize/base/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-poc

spec:
  replicas: 1

  selector:
    matchLabels:
      app: openshift-poc

  template:
    metadata:
      labels:
        app: openshift-poc

    spec:
      containers:
        - name: tomcat
          image: middleware-docker-local-dev.artifactory.cib.echonet/openshift-poc-tomcat:10.1.XX-jdk11-debian13
          imagePullPolicy: Always

          ports:
            - name: http
              containerPort: 8080

          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10

          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 30
            periodSeconds: 20

          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault

          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

`openshift-poc/kustomize/base/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: openshift-poc

spec:
  selector:
    app: openshift-poc

  ports:
    - name: http
      port: 8080
      targetPort: http
```



openshift-poc/kustomize/base/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
Overlay dev

openshift-poc/kustomize/overlays/dev/route.yaml

apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: openshift-poc

spec:
  to:
    kind: Service
    name: openshift-poc

  port:
    targetPort: http

  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect

openshift-poc/kustomize/overlays/dev/patch-deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-poc

spec:
  replicas: 1

  template:
    spec:
      containers:
        - name: tomcat
          env:
            - name: ENVIRONMENT
              value: dev

openshift-poc/kustomize/overlays/dev/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - route.yaml

patches:
  - path: patch-deployment.yaml
Mejor aún: gestionar el tag con Kustomize

En vez de editar deployment.yaml, puedes declarar la imagen en el kustomization.yaml.

Base:

images:
  - name: middleware-docker-local-dev.artifactory.cib.echonet/openshift-poc-tomcat
    newTag: 10.1.XX-jdk11-debian13

Así el deployment.yaml puede tener:

image: middleware-docker-local-dev.artifactory.cib.echonet/openshift-poc-tomcat

y Kustomize pone el tag.

Eso es más limpio para GitOps.

Argo CD usando Kustomize

openshift-poc/argocd/application-kustomize.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application

metadata:
  name: openshift-poc-kustomize

spec:
  project: default

  source:
    repoURL: https://bitbucket.cib.echonet/scm/middleware/kube-cicd.git
    targetRevision: feature/openshift-poc
    path: openshift-poc/kustomize/overlays/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: middleware-poc

  syncPolicy:
    automated:
      prune: true
      selfHeal: true

Argo CD detecta automáticamente que hay:

kustomization.yaml

y ejecuta conceptualmente:

kustomize build

No necesitas tener kustomize instalado localmente.

Checkov con Kustomize

Aquí encaja muy bien.

Tu pipeline puede hacer:

clone
  ↓
kustomize build
  ↓
checkov
  ↓
build imagen
  ↓
trivy

Conceptualmente:

kustomize build \
  openshift-poc/kustomize/overlays/dev \
  > /tmp/rendered.yaml

y:

checkov \
  -f /tmp/rendered.yaml \
  --framework kubernetes

Como no tienes herramientas locales, eso se hace en Argo Workflows con una imagen que tenga Kustomize y otra con Checkov.

Helm + Checkov

Igual:

helm template
  ↓
YAML
  ↓
checkov
Entonces tu pipeline completo puede validar ambos

Si quieres usar ambos como aprendizaje:

clone
   │
   ├── helm template
   │      ↓
   │    checkov
   │
   └── kustomize build
          ↓
        checkov

             ↓
          BuildKit
             ↓
         Artifactory DEV
             ↓
            Trivy
             ↓
          promotion
             ↓
      Artifactory RELEASE
             ↓
          Argo CD
             ↓
          OpenShift

Pero para desplegar, eliges uno:

Application Helm

o:

Application Kustomize



### Ejecución

VS Code
   │
   │ git push
   ▼
Bitbucket
   │
   ├──────────────► Argo Workflows UI
   │                    │
   │                    └── ejecuta build-tomcat.yaml
   │
   └──────────────► Argo CD
                        │
                        └── lee kustomization.yaml
                             y despliega en OpenShift


1. build-tomcat.yaml: lo ejecuta Argo Workflows

Este:

openshift-poc/
└── workflow/
    └── build-tomcat.yaml

es un:

kind: Workflow


Pero tú no tienes esas herramientas, así que usas la web de Argo Workflows:

Argo Workflows
      ↓
namespace correspondiente
      ↓
Submit New Workflow
      ↓
Edit using full workflow options
      ↓
pegas build-tomcat.yaml
      ↓
Submit

Eso ejecutará:

clone Bitbucket
      ↓
Checkov
      ↓
BuildKit
      ↓
Artifactory DEV
      ↓
Trivy
2. Los YAML de Kustomize NO los ejecutas individualmente

Tendrás:

openshift-poc/kustomize/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
│
└── overlays/
    └── dev/
        ├── route.yaml
        ├── patch-deployment.yaml
        └── kustomization.yaml

No haces:

kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f route.yaml

En GitOps, Argo CD lee el kustomization.yaml.

Tu Application apunta aquí:

source:
  repoURL: https://bitbucket.cib.echonet/scm/middleware/kube-cicd.git
  targetRevision: feature/openshift-poc
  path: openshift-poc/kustomize/overlays/dev

Argo CD encuentra:

openshift-poc/kustomize/overlays/dev/kustomization.yaml

y hace internamente el equivalente a:

kustomize build openshift-poc/kustomize/overlays/dev

El resultado será algo equivalente a:

Deployment
---
Service
---
Route

y Argo CD los aplica a OpenShift.

3. application-kustomize.yaml: hay que crearla una primera vez

Este fichero:

openshift-poc/argocd/application-kustomize.yaml

es especial porque alguien tiene que introducir esa Application en Argo CD.

Si tuvieras CLI:

kubectl apply -f openshift-poc/argocd/application-kustomize.yaml

Pero como no tienes kubectl, puedes hacerlo desde Argo CD UI:

Argo CD
   ↓
Applications
   ↓
New App
   ↓
Edit as YAML
   ↓
pegas application-kustomize.yaml
   ↓
Create

Esto se hace una vez.

A partir de ahí:

git push
   ↓
Argo CD detecta cambio
   ↓
kustomize build
   ↓
Sync
   ↓
OpenShift
4. Qué papel tendría kubectl u oc

Si mañana la empresa te proporciona oc, podrías hacer:

./oc.exe login ...

y:

./oc.exe project middleware-poc

Entonces podrías consultar:

./oc.exe get pods
./oc.exe get deployments
./oc.exe get services
./oc.exe get routes

También podrías aplicar recursos:

./oc.exe apply -f fichero.yaml

kubectl también funciona con gran parte de OpenShift:

kubectl get pods -n middleware-poc

Pero OpenShift añade recursos específicos como Route, BuildConfig, DeploymentConfig, SCC, etc., por lo que en OpenShift normalmente es más útil oc.

No necesitas ninguno de los dos para vuestro modelo GitOps si tienes acceso a Argo Workflows, Argo CD y la consola web de OpenShift.

Tu proceso real

Una vez tengas todos los ficheros:

VS CODE
│
├── openshift-poc/tomcat/
├── openshift-poc/workflow/
├── openshift-poc/kustomize/
└── openshift-poc/argocd/
│
│
├─ git commit
└─ git push
       │
       ▼
   BITBUCKET
       │
       │
       ├──────── CI ───────────────────────────┐
       │                                       │
       ▼                                       │
 ARGO WORKFLOWS                                │
       │                                       │
       ├─ clone                                │
       ├─ Checkov                              │
       ├─ BuildKit                             │
       ├─ push DEV                             │
       └─ Trivy                                │
                                               │
                              imagen aprobada  │
                                       │       │
                                       ▼       │
                                  ARTIFACTORY  │
                                       │
                                       │
       ┌──────── CD ───────────────────┘
       │
       ▼
    ARGO CD
       │
       │ lee:
       │ openshift-poc/kustomize/overlays/dev
       │
       ▼
 KUSTOMIZE BUILD
       │
       ├─ Deployment
       ├─ Service
       └─ Route
       │
       ▼
   OPENSHIFT
       │
       ▼
 middleware-poc
       │
       ├─ Deployment
       ├─ Pod
       ├─ Service
       └─ Route

Hay además una pieza que todavía debemos resolver correctamente: cómo pasa el pipeline de “Trivy OK” a cambiar el tag de Kustomize que observa Argo CD. No conviene que Argo CD despliegue automáticamente cualquier imagen que simplemente aparezca en Artifactory. Esa promoción debe ocurrir únicamente después de Checkov/Trivy/Sonar y es donde encaja el commit GitOps del nuevo newTag.