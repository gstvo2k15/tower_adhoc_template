POC completa: Bitbucket → Argo Workflows → Artifactory → Git → Argo CD → OpenShift

0. Objetivo

Esta guía crea una POC completa en el namespace existente:

middleware-poc

Flujo final:

git push a feature/openshift-poc
        │
        ▼
Bitbucket Webhook
        │
        ▼
Argo Events
        │
        ▼
Argo Workflow
        │
        ├── clona kube-cicd
        ├── construye openshift-poc/Dockerfile
        ├── publica la imagen en Artifactory
        ├── modifica deployment.yaml
        └── hace commit y push con [skip ci]
                    │
                    ▼
                Bitbucket
                    │
                    ▼
                 Argo CD
                    │
                    ▼
             namespace middleware-poc

1. Valores que debes sustituir

Busca y reemplaza estos valores en los ficheros:

BITBUCKET_HOST
BITBUCKET_PROJECT
BITBUCKET_USERNAME
BITBUCKET_TOKEN

ARTIFACTORY_REGISTRY
ARTIFACTORY_DOCKER_REPOSITORY
ARTIFACTORY_USERNAME
ARTIFACTORY_PASSWORD

OPENSHIFT_APPS_DOMAIN

Ejemplo:

BITBUCKET_HOST=bitbucket.empresa.local
BITBUCKET_PROJECT=MIDDLEWARE

ARTIFACTORY_REGISTRY=artifactory.empresa.local
ARTIFACTORY_DOCKER_REPOSITORY=docker-local

OPENSHIFT_APPS_DOMAIN=apps.cluster.empresa.local

Repositorio usado:

kube-cicd

Rama usada:

feature/openshift-poc

Namespace usado para todos los recursos de la POC:

middleware-poc

Namespace donde está Argo CD:

openshift-gitops

2. Requisitos previos

Comprueba:

oc whoami
oc get namespace middleware-poc
oc get crd workflows.argoproj.io
oc get crd applications.argoproj.io
oc get crd eventsources.argoproj.io
oc get crd sensors.argoproj.io
oc get crd eventbus.argoproj.io

Deben existir:

workflows.argoproj.io
applications.argoproj.io
eventsources.argoproj.io
sensors.argoproj.io
eventbus.argoproj.io

Si los CRD de Argo Events no existen, la parte de webhook no funcionará hasta que el administrador instale Argo Events.

Comprueba que Argo CD está instalado:

oc get pods -n openshift-gitops

3. Crear la rama

git clone https://BITBUCKET_HOST/scm/BITBUCKET_PROJECT/kube-cicd.git
cd kube-cicd

git checkout -b feature/openshift-poc

Si la rama ya existe:

git checkout feature/openshift-poc
git pull

4. Estructura completa

Crea los directorios:

mkdir -p openshift-poc/src
mkdir -p openshift-poc/deploy/dev
mkdir -p openshift-poc/argocd
mkdir -p openshift-poc/workflows
mkdir -p openshift-poc/events
mkdir -p openshift-poc/bootstrap

Árbol final:

kube-cicd/
├── .gitignore
└── openshift-poc/
    ├── Dockerfile
    ├── src/
    │   └── index.html
    ├── deploy/
    │   └── dev/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       ├── route.yaml
    │       └── kustomization.yaml
    ├── argocd/
    │   └── application-dev.yaml
    ├── workflows/
    │   ├── serviceaccount.yaml
    │   ├── role.yaml
    │   ├── rolebinding.yaml
    │   └── workflow-template.yaml
    ├── events/
    │   ├── eventbus.yaml
    │   ├── eventsource.yaml
    │   ├── eventsource-route.yaml
    │   ├── sensor-serviceaccount.yaml
    │   ├── sensor-role.yaml
    │   ├── sensor-rolebinding.yaml
    │   └── sensor.yaml
    └── bootstrap/
        ├── argocd-repository-secret.example.yaml
        ├── bitbucket-secret.example.yaml
        └── artifactory-secret.example.yaml

5. Fichero .gitignore

Ruta:

.gitignore

Contenido:

# Credenciales reales
openshift-poc/bootstrap/*-secret.yaml
openshift-poc/bootstrap/*.local.yaml

# Archivos temporales
*.tmp
*.bak
.env

6. Aplicación de prueba

6.1 openshift-poc/src/index.html

<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>Middleware POC</title>
</head>
<body>
  <h1>Middleware POC funcionando</h1>
  <p>Imagen construida por Argo Workflows y desplegada por Argo CD.</p>
</body>
</html>

6.2 openshift-poc/Dockerfile

FROM registry.access.redhat.com/ubi9/httpd-24:latest

COPY src/ /var/www/html/

EXPOSE 8080

7. Manifiestos que Argo CD desplegará

7.1 openshift-poc/deploy/dev/deployment.yaml

Inicialmente usa una imagen pública. Después el Workflow sustituirá automáticamente la línea image: por la imagen publicada en Artifactory.

apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-poc
  labels:
    app: openshift-poc
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
        - name: openshift-poc
          image: registry.access.redhat.com/ubi9/httpd-24:latest
          imagePullPolicy: Always

          ports:
            - name: http
              containerPort: 8080
              protocol: TCP

          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10

          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 20
            periodSeconds: 20

          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            seccompProfile:
              type: RuntimeDefault

7.2 openshift-poc/deploy/dev/service.yaml

apiVersion: v1
kind: Service
metadata:
  name: openshift-poc
  labels:
    app: openshift-poc
spec:
  type: ClusterIP

  selector:
    app: openshift-poc

  ports:
    - name: http
      protocol: TCP
      port: 8080
      targetPort: http

7.3 openshift-poc/deploy/dev/route.yaml

apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: openshift-poc
  labels:
    app: openshift-poc
spec:
  to:
    kind: Service
    name: openshift-poc
    weight: 100

  port:
    targetPort: http

  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect

7.4 openshift-poc/deploy/dev/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - route.yaml

8. Application de Argo CD

8.1 openshift-poc/argocd/application-dev.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-poc-dev
  namespace: openshift-gitops
spec:
  project: default

  source:
    repoURL: https://BITBUCKET_HOST/scm/BITBUCKET_PROJECT/kube-cicd.git
    targetRevision: feature/openshift-poc
    path: openshift-poc/deploy/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: middleware-poc

  syncPolicy:
    automated:
      prune: true
      selfHeal: true

    syncOptions:
      - ApplyOutOfSyncOnly=true

9. Credenciales

Los siguientes ficheros son plantillas. No subas credenciales reales a Git.

9.1 openshift-poc/bootstrap/argocd-repository-secret.example.yaml

Este secreto permite a Argo CD leer el repositorio privado de Bitbucket.

apiVersion: v1
kind: Secret
metadata:
  name: repo-kube-cicd
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://BITBUCKET_HOST/scm/BITBUCKET_PROJECT/kube-cicd.git
  username: BITBUCKET_USERNAME
  password: BITBUCKET_TOKEN

9.2 openshift-poc/bootstrap/bitbucket-secret.example.yaml

Este secreto lo utiliza el Workflow para clonar y hacer push.

apiVersion: v1
kind: Secret
metadata:
  name: bitbucket-credentials
  namespace: middleware-poc
type: Opaque
stringData:
  username: BITBUCKET_USERNAME
  token: BITBUCKET_TOKEN

9.3 openshift-poc/bootstrap/artifactory-secret.example.yaml

Este secreto lo utiliza Buildah para hacer login y push en Artifactory.

apiVersion: v1
kind: Secret
metadata:
  name: artifactory-credentials
  namespace: middleware-poc
type: Opaque
stringData:
  username: ARTIFACTORY_USERNAME
  password: ARTIFACTORY_PASSWORD

10. ServiceAccount y RBAC del Workflow

10.1 openshift-poc/workflows/serviceaccount.yaml

apiVersion: v1
kind: ServiceAccount
metadata:
  name: openshift-poc-workflow
  namespace: middleware-poc

10.2 openshift-poc/workflows/role.yaml

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
      - patch
      - update

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

10.3 openshift-poc/workflows/rolebinding.yaml

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

11. WorkflowTemplate completo

11.1 openshift-poc/workflows/workflow-template.yaml

Este Workflow:

Comprueba si el webhook contiene [skip ci].

Clona Bitbucket.

Obtiene el SHA corto del commit.

Construye la imagen con Buildah.

Publica la imagen en Artifactory.

Sustituye image: en deployment.yaml.

Hace commit y push.

El commit automático usa [skip ci] para que el webhook siguiente no vuelva a construir.

apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: openshift-poc-build
  namespace: middleware-poc
spec:
  serviceAccountName: openshift-poc-workflow

  entrypoint: pipeline

  arguments:
    parameters:
      - name: webhook-body
        value: "{}"

      - name: git-url
        value: https://BITBUCKET_HOST/scm/BITBUCKET_PROJECT/kube-cicd.git

      - name: git-branch
        value: feature/openshift-poc

      - name: image-repository
        value: ARTIFACTORY_REGISTRY/ARTIFACTORY_DOCKER_REPOSITORY/openshift-poc

  volumeClaimTemplates:
    - metadata:
        name: workspace
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi

  templates:
    - name: pipeline
      steps:
        - - name: guard
            template: guard
            arguments:
              parameters:
                - name: webhook-body
                  value: "{{workflow.parameters.webhook-body}}"

        - - name: clone
            template: clone
            when: "{{steps.guard.outputs.parameters.run}} == true"

        - - name: build-and-push
            template: build-and-push
            when: "{{steps.guard.outputs.parameters.run}} == true"
            arguments:
              parameters:
                - name: commit-sha
                  value: "{{steps.clone.outputs.parameters.commit-sha}}"

        - - name: update-git
            template: update-git
            when: "{{steps.guard.outputs.parameters.run}} == true"
            arguments:
              parameters:
                - name: commit-sha
                  value: "{{steps.clone.outputs.parameters.commit-sha}}"

    - name: guard
      inputs:
        parameters:
          - name: webhook-body
      outputs:
        parameters:
          - name: run
            valueFrom:
              path: /tmp/run
      container:
        image: docker.io/alpine:3.20
        command:
          - /bin/sh
          - -ec
        args:
          - |
            apk add --no-cache jq

            printf '%s' '{{inputs.parameters.webhook-body}}' > /tmp/webhook.json

            if jq -e '.. | .message? // empty | select(contains("[skip ci]"))' \
              /tmp/webhook.json >/dev/null 2>&1; then
              echo false > /tmp/run
              echo "Commit automático detectado. No se ejecuta otra construcción."
            else
              echo true > /tmp/run
              echo "El Workflow continuará."
            fi

    - name: clone
      outputs:
        parameters:
          - name: commit-sha
            valueFrom:
              path: /tmp/commit-sha
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: "{{workflow.name}}-workspace"
      container:
        image: docker.io/alpine/git:2.45.2
        workingDir: /workspace
        command:
          - /bin/sh
          - -ec
        env:
          - name: BITBUCKET_USERNAME
            valueFrom:
              secretKeyRef:
                name: bitbucket-credentials
                key: username

          - name: BITBUCKET_TOKEN
            valueFrom:
              secretKeyRef:
                name: bitbucket-credentials
                key: token

        volumeMounts:
          - name: workspace
            mountPath: /workspace

        args:
          - |
            rm -rf /workspace/repo

            cat >/tmp/askpass.sh <<'EOF'
            #!/bin/sh
            case "$1" in
              *Username*) printf '%s\n' "$BITBUCKET_USERNAME" ;;
              *Password*) printf '%s\n' "$BITBUCKET_TOKEN" ;;
            esac
            EOF

            chmod 700 /tmp/askpass.sh
            export GIT_ASKPASS=/tmp/askpass.sh
            export GIT_TERMINAL_PROMPT=0

            git clone \
              --branch "{{workflow.parameters.git-branch}}" \
              --single-branch \
              "{{workflow.parameters.git-url}}" \
              /workspace/repo

            cd /workspace/repo
            git rev-parse --short=12 HEAD > /tmp/commit-sha

    - name: build-and-push
      inputs:
        parameters:
          - name: commit-sha

      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: "{{workflow.name}}-workspace"

      container:
        image: quay.io/buildah/stable:v1.35
        workingDir: /workspace/repo/openshift-poc

        securityContext:
          privileged: true

        env:
          - name: ARTIFACTORY_USERNAME
            valueFrom:
              secretKeyRef:
                name: artifactory-credentials
                key: username

          - name: ARTIFACTORY_PASSWORD
            valueFrom:
              secretKeyRef:
                name: artifactory-credentials
                key: password

        volumeMounts:
          - name: workspace
            mountPath: /workspace

        command:
          - /bin/bash
          - -ec

        args:
          - |
            IMAGE="{{workflow.parameters.image-repository}}:{{inputs.parameters.commit-sha}}"

            buildah login \
              --username "$ARTIFACTORY_USERNAME" \
              --password "$ARTIFACTORY_PASSWORD" \
              ARTIFACTORY_REGISTRY

            buildah bud \
              --storage-driver=vfs \
              --format=docker \
              --tag "$IMAGE" \
              .

            buildah push \
              --storage-driver=vfs \
              "$IMAGE"

            printf '%s\n' "$IMAGE" >/workspace/image.txt

    - name: update-git
      inputs:
        parameters:
          - name: commit-sha

      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: "{{workflow.name}}-workspace"

      container:
        image: docker.io/alpine/git:2.45.2
        workingDir: /workspace/repo

        env:
          - name: BITBUCKET_USERNAME
            valueFrom:
              secretKeyRef:
                name: bitbucket-credentials
                key: username

          - name: BITBUCKET_TOKEN
            valueFrom:
              secretKeyRef:
                name: bitbucket-credentials
                key: token

        volumeMounts:
          - name: workspace
            mountPath: /workspace

        command:
          - /bin/sh
          - -ec

        args:
          - |
            IMAGE="$(cat /workspace/image.txt)"
            MANIFEST="openshift-poc/deploy/dev/deployment.yaml"

            sed -i \
              "s#^[[:space:]]*image:.*#          image: ${IMAGE}#" \
              "$MANIFEST"

            git config user.name "argo-workflows"
            git config user.email "argo-workflows@empresa.local"

            if git diff --quiet -- "$MANIFEST"; then
              echo "No hay cambios en deployment.yaml."
              exit 0
            fi

            git add "$MANIFEST"
            git commit -m "Update openshift-poc image to {{inputs.parameters.commit-sha}} [skip ci]"

            cat >/tmp/askpass.sh <<'EOF'
            #!/bin/sh
            case "$1" in
              *Username*) printf '%s\n' "$BITBUCKET_USERNAME" ;;
              *Password*) printf '%s\n' "$BITBUCKET_TOKEN" ;;
            esac
            EOF

            chmod 700 /tmp/askpass.sh
            export GIT_ASKPASS=/tmp/askpass.sh
            export GIT_TERMINAL_PROMPT=0

            git push origin \
              "HEAD:{{workflow.parameters.git-branch}}"

Nota importante sobre el PVC

Argo crea un PVC basado en volumeClaimTemplates.

Comprueba el nombre real:

oc get pvc -n middleware-poc

Si tu versión de Argo no resuelve correctamente:

claimName: "{{workflow.name}}-workspace"

el administrador deberá revisar la configuración del controlador. Otra alternativa es utilizar artefactos en vez de un PVC.

12. Permiso privilegiado para Buildah

El paso Buildah utiliza:

securityContext:
  privileged: true

Un administrador debe ejecutar:

oc adm policy add-scc-to-user \
  privileged \
  -z openshift-poc-workflow \
  -n middleware-poc

Comprueba:

oc adm policy who-can use scc privileged | grep openshift-poc-workflow

Si no tienes permisos para ejecutar oc adm, debe hacerlo el administrador del clúster.

13. Argo Events

13.1 openshift-poc/events/eventbus.yaml

apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
  namespace: middleware-poc
spec:
  native:
    replicas: 1

13.2 openshift-poc/events/eventsource.yaml

apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: bitbucket
  namespace: middleware-poc
spec:
  eventBusName: default

  service:
    ports:
      - name: webhook
        port: 12000
        targetPort: 12000

  webhook:
    push:
      endpoint: /bitbucket
      method: POST
      port: "12000"

13.3 openshift-poc/events/eventsource-route.yaml

El Service creado por Argo Events normalmente se llama:

bitbucket-eventsource-svc

apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: bitbucket-webhook
  namespace: middleware-poc
spec:
  to:
    kind: Service
    name: bitbucket-eventsource-svc
    weight: 100

  port:
    targetPort: webhook

  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect

Después de crear el EventSource, confirma el nombre real:

oc get service -n middleware-poc | grep bitbucket

Si el Service tiene otro nombre, modifica spec.to.name en la Route.

14. RBAC del Sensor

14.1 openshift-poc/events/sensor-serviceaccount.yaml

apiVersion: v1
kind: ServiceAccount
metadata:
  name: openshift-poc-sensor
  namespace: middleware-poc

14.2 openshift-poc/events/sensor-role.yaml

apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: openshift-poc-sensor
  namespace: middleware-poc
rules:
  - apiGroups:
      - argoproj.io
    resources:
      - workflows
    verbs:
      - create
      - get
      - list
      - watch

14.3 openshift-poc/events/sensor-rolebinding.yaml

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: openshift-poc-sensor
  namespace: middleware-poc
subjects:
  - kind: ServiceAccount
    name: openshift-poc-sensor
    namespace: middleware-poc
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: openshift-poc-sensor

15. Sensor

15.1 openshift-poc/events/sensor.yaml

El Sensor recibe el body completo de Bitbucket y crea un Workflow que referencia el WorkflowTemplate.

apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: bitbucket-push
  namespace: middleware-poc
spec:
  eventBusName: default

  template:
    serviceAccountName: openshift-poc-sensor

  dependencies:
    - name: bitbucket-push
      eventSourceName: bitbucket
      eventName: push

  triggers:
    - template:
        name: start-openshift-poc-build

        k8s:
          operation: create

          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: openshift-poc-build-
                namespace: middleware-poc
              spec:
                workflowTemplateRef:
                  name: openshift-poc-build

                arguments:
                  parameters:
                    - name: webhook-body
                      value: "{}"

          parameters:
            - src:
                dependencyName: bitbucket-push
                dataKey: body
              dest: spec.arguments.parameters.0.value

16. Crear los ficheros en Git

Después de crear todos los ficheros:

git status
git add .gitignore openshift-poc
git commit -m "Add complete OpenShift Argo POC"
git push -u origin feature/openshift-poc

Comprueba en Bitbucket que aparecen todos los ficheros.

17. Crear secretos reales sin subirlos a Git

17.1 Secreto de Argo CD

cp \
  openshift-poc/bootstrap/argocd-repository-secret.example.yaml \
  /tmp/argocd-repository-secret.yaml

vi /tmp/argocd-repository-secret.yaml
oc apply -f /tmp/argocd-repository-secret.yaml
rm -f /tmp/argocd-repository-secret.yaml

Comprueba:

oc get secret repo-kube-cicd -n openshift-gitops

17.2 Secreto de Bitbucket

cp \
  openshift-poc/bootstrap/bitbucket-secret.example.yaml \
  /tmp/bitbucket-secret.yaml

vi /tmp/bitbucket-secret.yaml
oc apply -f /tmp/bitbucket-secret.yaml
rm -f /tmp/bitbucket-secret.yaml

Comprueba:

oc get secret bitbucket-credentials -n middleware-poc

17.3 Secreto de Artifactory

cp \
  openshift-poc/bootstrap/artifactory-secret.example.yaml \
  /tmp/artifactory-secret.yaml

vi /tmp/artifactory-secret.yaml
oc apply -f /tmp/artifactory-secret.yaml
rm -f /tmp/artifactory-secret.yaml

Comprueba:

oc get secret artifactory-credentials -n middleware-poc

18. Permitir que Argo CD gestione middleware-poc

Un administrador debe etiquetar el namespace:

oc label namespace middleware-poc \
  argocd.argoproj.io/managed-by=openshift-gitops \
  --overwrite

Comprueba:

oc get namespace middleware-poc \
  -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by}{"\n"}'

Resultado esperado:

openshift-gitops

19. Aplicar Argo CD

oc apply \
  -f openshift-poc/argocd/application-dev.yaml

Comprueba:

oc get application openshift-poc-dev \
  -n openshift-gitops

Estado:

oc get application openshift-poc-dev \
  -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'

Resultado esperado:

Synced Healthy

Comprueba los recursos:

oc get deployment,pod,service,route \
  -n middleware-poc

20. Aplicar Workflow y RBAC

oc apply -f openshift-poc/workflows/serviceaccount.yaml
oc apply -f openshift-poc/workflows/role.yaml
oc apply -f openshift-poc/workflows/rolebinding.yaml
oc apply -f openshift-poc/workflows/workflow-template.yaml

Comprueba:

oc get serviceaccount openshift-poc-workflow \
  -n middleware-poc

oc get workflowtemplate openshift-poc-build \
  -n middleware-poc

Aplica el SCC privilegiado:

oc adm policy add-scc-to-user \
  privileged \
  -z openshift-poc-workflow \
  -n middleware-poc

21. Probar el Workflow manualmente antes del webhook

Crea un Workflow desde el template:

argo submit \
  --from workflowtemplate/openshift-poc-build \
  -n middleware-poc \
  --watch

Si no tienes el CLI argo, crea este fichero temporal:

cat >/tmp/manual-workflow.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: openshift-poc-manual-
  namespace: middleware-poc
spec:
  workflowTemplateRef:
    name: openshift-poc-build
EOF

Aplica:

oc create -f /tmp/manual-workflow.yaml
rm -f /tmp/manual-workflow.yaml

Lista Workflows:

oc get workflows -n middleware-poc

Observa pods:

oc get pods -n middleware-poc -w

Logs del Workflow:

argo logs @latest -n middleware-poc

Sin CLI:

oc get pods -n middleware-poc
oc logs POD -n middleware-poc

Comprueba en Artifactory que existe una imagen similar a:

ARTIFACTORY_REGISTRY/ARTIFACTORY_DOCKER_REPOSITORY/openshift-poc:SHA

Comprueba en Bitbucket que el Workflow creó un commit:

Update openshift-poc image to SHA [skip ci]

Comprueba que deployment.yaml ahora contiene:

image: ARTIFACTORY_REGISTRY/ARTIFACTORY_DOCKER_REPOSITORY/openshift-poc:SHA

Comprueba Argo CD:

oc get application openshift-poc-dev \
  -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'

Comprueba el rollout:

oc rollout status deployment/openshift-poc \
  -n middleware-poc

22. Configurar pull de Artifactory en OpenShift

Aunque el Workflow pueda publicar la imagen, el Deployment también necesita descargarla.

Crea un pull secret:

oc create secret docker-registry artifactory-pull-secret \
  --docker-server=ARTIFACTORY_REGISTRY \
  --docker-username=ARTIFACTORY_USERNAME \
  --docker-password=ARTIFACTORY_PASSWORD \
  -n middleware-poc

Enlázalo al ServiceAccount por defecto:

oc secrets link default \
  artifactory-pull-secret \
  --for=pull \
  -n middleware-poc

Comprueba:

oc get serviceaccount default \
  -n middleware-poc \
  -o yaml

Debe aparecer:

imagePullSecrets:
  - name: artifactory-pull-secret

23. Aplicar Argo Events

oc apply -f openshift-poc/events/eventbus.yaml

oc apply -f openshift-poc/events/sensor-serviceaccount.yaml
oc apply -f openshift-poc/events/sensor-role.yaml
oc apply -f openshift-poc/events/sensor-rolebinding.yaml

oc apply -f openshift-poc/events/eventsource.yaml
oc apply -f openshift-poc/events/sensor.yaml

Espera:

oc get eventbus,eventsource,sensor \
  -n middleware-poc

Comprueba pods:

oc get pods -n middleware-poc | grep -E 'eventbus|eventsource|sensor'

Comprueba el Service generado:

oc get service -n middleware-poc | grep bitbucket

Aplica la Route:

oc apply \
  -f openshift-poc/events/eventsource-route.yaml

Obtén la URL:

oc get route bitbucket-webhook \
  -n middleware-poc \
  -o jsonpath='https://{.spec.host}/bitbucket{"\n"}'

Ejemplo:

https://bitbucket-webhook-middleware-poc.OPENSHIFT_APPS_DOMAIN/bitbucket

24. Probar el webhook sin Bitbucket

Ejecuta:

curl -k \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{
        "eventKey": "repo:refs_changed",
        "changes": [
          {
            "ref": {
              "displayId": "feature/openshift-poc"
            },
            "commits": [
              {
                "message": "Prueba manual"
              }
            ]
          }
        ]
      }' \
  "https://$(oc get route bitbucket-webhook \
      -n middleware-poc \
      -o jsonpath='{.spec.host}')/bitbucket"

Comprueba:

oc get workflows -n middleware-poc

Debe aparecer un Workflow nuevo.

Logs del Sensor:

oc logs \
  -l sensor-name=bitbucket-push \
  -n middleware-poc \
  --tail=200

Logs del EventSource:

oc logs \
  -l eventsource-name=bitbucket \
  -n middleware-poc \
  --tail=200

25. Crear el webhook en Bitbucket

En el repositorio kube-cicd:

Repository settings
→ Webhooks
→ Create webhook

Configura:

Name:
OpenShift POC

URL:
https://bitbucket-webhook-middleware-poc.OPENSHIFT_APPS_DOMAIN/bitbucket

Event:
Repository push

Guarda el webhook.

Haz un cambio real:

echo "<!-- webhook test -->" >> openshift-poc/src/index.html

git add openshift-poc/src/index.html
git commit -m "Test OpenShift POC webhook"
git push origin feature/openshift-poc

Resultado esperado:

1. Bitbucket envía el webhook.
2. Argo Events crea un Workflow.
3. El Workflow construye la imagen.
4. El Workflow publica la imagen en Artifactory.
5. El Workflow modifica deployment.yaml.
6. El Workflow hace commit con [skip ci].
7. Bitbucket genera otro webhook.
8. El Workflow guard detecta [skip ci] y no construye.
9. Argo CD detecta el nuevo deployment.yaml.
10. OpenShift actualiza el Deployment.

26. Validación final

26.1 Workflows

oc get workflows -n middleware-poc

26.2 Imagen desplegada

oc get deployment openshift-poc \
  -n middleware-poc \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

Debe devolver Artifactory:

ARTIFACTORY_REGISTRY/ARTIFACTORY_DOCKER_REPOSITORY/openshift-poc:SHA

26.3 Pods

oc get pods -n middleware-poc

26.4 Rollout

oc rollout status deployment/openshift-poc \
  -n middleware-poc

26.5 Route

oc get route openshift-poc \
  -n middleware-poc \
  -o jsonpath='https://{.spec.host}{"\n"}'

Abre la URL. Debe aparecer:

Middleware POC funcionando

27. Diagnóstico de errores

Argo CD muestra ComparisonError

oc describe application openshift-poc-dev \
  -n openshift-gitops

Revisa:

repoURL
targetRevision
path
credenciales de Bitbucket

Argo CD no puede desplegar en middleware-poc

Comprueba:

oc get namespace middleware-poc --show-labels

Debe existir:

argocd.argoproj.io/managed-by=openshift-gitops

Buildah muestra permission denied

Comprueba SCC:

oc adm policy who-can use scc privileged

El ServiceAccount debe aparecer:

system:serviceaccount:middleware-poc:openshift-poc-workflow

Buildah no puede publicar

Comprueba el secreto:

oc get secret artifactory-credentials \
  -n middleware-poc

Comprueba:

ARTIFACTORY_REGISTRY
ARTIFACTORY_DOCKER_REPOSITORY
usuario
contraseña/token
permisos de deploy en Artifactory

OpenShift no puede descargar la imagen

oc describe pod POD -n middleware-poc

Si aparece:

ImagePullBackOff
unauthorized

revisa:

oc get secret artifactory-pull-secret \
  -n middleware-poc

oc get serviceaccount default \
  -n middleware-poc \
  -o yaml

El Sensor no crea Workflows

oc logs \
  -l sensor-name=bitbucket-push \
  -n middleware-poc

Comprueba permisos:

oc auth can-i create workflows.argoproj.io \
  --as=system:serviceaccount:middleware-poc:openshift-poc-sensor \
  -n middleware-poc

Debe devolver:

yes

La Route del webhook devuelve error

Comprueba:

oc get route bitbucket-webhook -n middleware-poc
oc get service -n middleware-poc | grep bitbucket
oc get endpoints -n middleware-poc | grep bitbucket

28. Orden exacto de ejecución

Ejecuta en este orden:

1. Crear todos los ficheros.
2. Sustituir los placeholders.
3. Commit y push a feature/openshift-poc.
4. Crear los tres secretos.
5. Etiquetar middleware-poc para Argo CD.
6. Crear la Application.
7. Comprobar Synced y Healthy.
8. Crear ServiceAccount y RBAC del Workflow.
9. Crear WorkflowTemplate.
10. Dar SCC privileged al ServiceAccount.
11. Crear pull secret de Artifactory.
12. Ejecutar el Workflow manualmente.
13. Confirmar imagen en Artifactory.
14. Confirmar commit automático en Bitbucket.
15. Confirmar despliegue de Argo CD.
16. Crear EventBus.
17. Crear EventSource.
18. Crear Sensor y su RBAC.
19. Crear Route del webhook.
20. Probar con curl.
21. Crear webhook en Bitbucket.
22. Hacer push de prueba.
23. Verificar Workflow, Artifactory, Git, Argo CD y OpenShift.

29. Resumen de responsabilidades

Bitbucket:
  Guarda Dockerfile, código y YAML.

Argo Events:
  Recibe el webhook.

Argo Workflows:
  Construye y publica la imagen.
  Actualiza Git.

Artifactory:
  Guarda la imagen Docker.

Argo CD:
  Observa deployment.yaml.
  Sincroniza OpenShift.

OpenShift:
  Ejecuta la imagen dentro de middleware-poc.