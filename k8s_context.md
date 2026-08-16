```bash
https://github.com/argoproj/argo-cd/releases/tag/v3.4.5

https://github.com/argoproj/argo-cd/releases/download/v3.4.5/argocd-windows-amd64.exe?

kubectl config current-context

kubectl config get-contexts

echo "$KUBECONFIG"
ls -la ~/.kube/config

~/.kube/config

kubectl config view --raw --flatten > kubeconfig-windows.yaml


### Llevarlo a wintel

New-Item -ItemType Directory -Force "$HOME\.kube"

scp usuario@TU_SERVER:/ruta/kubeconfig-windows.yaml $HOME\.kube\config



kubectl config get-contexts
kubectl config current-context
kubectl get nodes
```