```bash
kubectl --kubeconfig ~/openshift-kubeconfig.yaml \
  get sa argocd-poc -n middleware-poc

kubectl --kubeconfig ~/openshift-kubeconfig.yaml \
  auth can-i create secrets -n middleware-poc

```


```bash
cat >/tmp/argocd-token-test.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: argocd-token-test
  namespace: middleware-poc
  annotations:
    kubernetes.io/service-account.name: argocd-poc
type: kubernetes.io/service-account-token
EOF

kubectl --kubeconfig ~/openshift-kubeconfig.yaml \
  create -f /tmp/argocd-token-test.yaml
```