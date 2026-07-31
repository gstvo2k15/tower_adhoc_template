FROM debian:13

ARG TOMCAT_VERSION=10.1.55

ENV DEBIAN_FRONTEND=noninteractive
ENV CATALINA_HOME=/opt/tomcat
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${CATALINA_HOME}/bin:${JAVA_HOME}/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-21-jre-headless \
        curl \
        ca-certificates \
        tar && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt && \
    curl -fsSL \
        "https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
        -o /tmp/tomcat.tar.gz && \
    tar -xzf /tmp/tomcat.tar.gz -C /opt && \
    mv "/opt/apache-tomcat-${TOMCAT_VERSION}" "${CATALINA_HOME}" && \
    rm /tmp/tomcat.tar.gz

RUN rm -rf \
    "${CATALINA_HOME}/webapps/docs" \
    "${CATALINA_HOME}/webapps/examples" \
    "${CATALINA_HOME}/webapps/host-manager" \
    "${CATALINA_HOME}/webapps/manager"

WORKDIR ${CATALINA_HOME}

EXPOSE 8080

CMD ["catalina.sh", "run"]




root@ub24nginx:~# docker images
IMAGE                ID             DISK USAGE   CONTENT SIZE   EXTRA
alpine-tomcat10:v2   389145c1fc61        239MB             0B    U
debian13:v2          ebb392836c73        368MB             0B    U



############################
###### Alpine version ######
############################
FROM alpine:3.24

ARG TOMCAT_VERSION=10.1.57

ENV CATALINA_HOME=/opt/tomcat
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk
ENV PATH=$CATALINA_HOME/bin:$JAVA_HOME/bin:$PATH

RUN apk add --no-cache \
    openjdk21-jre-headless \
    ca-certificates \
    tzdata \
    wget \
    tar

RUN addgroup -S tomcat && \
    adduser -S -G tomcat tomcat

RUN mkdir -p $CATALINA_HOME && \
    wget https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -O /tmp/tomcat.tar.gz && \
    tar -xzf /tmp/tomcat.tar.gz --strip-components=1 -C $CATALINA_HOME && \
    rm /tmp/tomcat.tar.gz && \
    rm -rf \
        $CATALINA_HOME/webapps/docs \
        $CATALINA_HOME/webapps/examples \
        $CATALINA_HOME/webapps/host-manager \
        $CATALINA_HOME/webapps/manager

RUN chown -R tomcat:tomcat $CATALINA_HOME

WORKDIR $CATALINA_HOME

USER tomcat

EXPOSE 8080

CMD ["catalina.sh","run"]




kube-cicd/
└── openshift-poc/
    ├── Dockerfile
    ├── src/
    ├── deploy/
    │   └── dev/
    └── workflows/


cd openshift-poc

mkdir -p {src,argocd,workflows}
mkdir -p deploy/dev

openshift-poc/
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
    └── workflows/

src/index.html
<!doctype html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>Middleware POC</title>
</head>
<body>
    <h1>Middleware POC working!</h1>
    <p>Deployed App with Argo CD.</p>
</body>
</html>


Dockerfile
FROM registry.access.redhat.com/ubi9/httpd-24:latest

COPY src/ /var/www/html/

EXPOSE 8080


deploy/dev/deployment.yaml
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
          imagePullPolicy: IfNotPresent

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


deploy/dev/service.yaml
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


deploy/dev/route.yaml
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


deploy/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - route.yaml


oc kustomize openshift-poc/deploy/dev


oc apply \
  --dry-run=server \
  -k openshift-poc/deploy/dev \
  -n middleware-poc


git add openshift-poc

git commit -m "Add OpenShift POC manifests"

git push -u origin feature/openshift-poc


oc label namespace middleware-poc \
  argocd.argoproj.io/managed-by=openshift-gitops \
  --overwrite


oc get namespace middleware-poc \
  -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by}{"\n"}'


argocd/application-dev.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-poc-dev
  namespace: openshift-gitops

spec:
  project: default

  source:
    repoURL: https://bitbucket.empresa.local/scm/PROYECTO/kube-cicd.git
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



Debes modificar únicamente:

repoURL: https://bitbucket.empresa.local/scm/PROYECTO/kube-cicd.git

targetRevision es la rama observada y path es el directorio que contiene los manifiestos.


git add openshift-poc/argocd/application-dev.yaml

git commit -m "Add Argo CD application"

git push






Si Bitbucket es privado, crea el secreto directamente en OpenShift.

No guardes este archivo con credenciales reales en Git.

cat >/tmp/repo-kube-cicd.yaml <<'EOF'
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
  url: https://bitbucket.empresa.local/scm/PROYECTO/kube-cicd.git
  username: USUARIO_BITBUCKET
  password: TOKEN_BITBUCKET
EOF



vi /tmp/repo-kube-cicd.yaml




oc apply -f /tmp/repo-kube-cicd.yaml




rm -f /tmp/repo-kube-cicd.yaml


oc get secret repo-kube-cicd \
  -n openshift-gitops


oc apply \
  -f openshift-poc/argocd/application-dev.yaml

oc get application openshift-poc-dev \
  -n openshift-gitops

oc describe application openshift-poc-dev \
  -n openshift-gitops

oc get application openshift-poc-dev \
  -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'

oc get deployment,pod,service,route \
  -n middleware-poc


oc rollout status deployment/openshift-poc \
  -n middleware-poc


oc logs \
  deployment/openshift-poc \
  -n middleware-poc

oc get route openshift-poc \
  -n middleware-poc \
  -o jsonpath='https://{.spec.host}{"\n"}'



Bitbucket
kube-cicd
feature/openshift-poc
        │
        │ openshift-poc/deploy/dev
        ▼
Argo CD
openshift-poc-dev
        │
        ▼
Namespace
middleware-poc
        │
        ├── Deployment/openshift-poc
        ├── Service/openshift-poc
        └── Route/openshift-poc



Bitbucket → Argo CD → OpenShift



El siguiente bloque será:

Dockerfile → Argo Workflow → Artifactory → cambio de imagen en Git → Argo CD



