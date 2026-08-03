Primero puedes comprobar si Vault Injector existe en tu OpenShift:

`$OC get pods -n middleware-poc`

Y también mirar si otros workloads de middleware-poc tienen anotaciones Vault:

`$OC get deployments -n middleware-poc -o yaml | grep -i "vault.hashicorp.com" -A5 -B2`

Si no sale nada, seguramente tendremos que autenticar Bitbucket y Artifactory mediante Secret, no Vault.