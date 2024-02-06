# Helm chart for Vault (and External Secrets) automatic deployment

This chart utilizes Vault helm chart to deploy in multiple modes (stand-alone or HA) with some initial scripts.

We use additional scripts to initialize and unseal Vault pods. It can also add permissions for External Secrets operator that uses KV2 store.

Please note that for External Secrets initialization with Vault the ESO should be already deployed.


## Installation
Basic deploy:
```bash
helm repo add alpacked-security-hardening https://alpacked.github.io/security-hardening-helm

helm install vault alpacked-security-hardening/vault -n vault-system --create-namespace --atomic --wait
```

Install with External Secrets Operator:
```bash
helm repo add external-secrets https://charts.external-secrets.io

helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace --wait \
  --set installCRDs=true

helm install [...] \
  --set esoInit.enabled=true \
  --set esoInit.namespace="external-secrets-system" # Set location of ESO in cluster
```

Enable vault-injector:
```bash
helm install [...] \
  --set vault.injector.enabled=true
```

Enable HA mode w/ raft mode:
```bash
helm install [...] \
 --set vault.server.ha.enabled=true \
 --set vault.server.ha.raft.enabled=true
```

Test the creation of external secret from Vault:
```bash
helm test vault
```
