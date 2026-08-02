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