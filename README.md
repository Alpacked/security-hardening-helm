# Helm Chart for Vault (and External Secrets) Automatic Deployment

This chart leverages the Vault Helm chart for deployment in various modes (stand-alone or high availability (HA)) and includes initial scripts for setup.

We use additional scripts (jobs) to initialize and unseal Vault pods. These scripts also configure permissions for the External Secrets Operator, which utilizes the KV2 store:

- **vault-init.sh**:
This script checks the status of ready Vault pods and performs the unseal process. The `vault-0` pod is designated as the leader, with the remaining pods serving as followers in HA raft mode (if enabled).

- **vault-init-eso.sh**:
Executed after `vault-init.sh`, this script enables the `kubernetes` authentication method in Vault, initiates the KV2 secret engine, and adds a read-only policy and role for the ESO service account.
It is important to note that the External Secrets Operator should already be deployed before initializing it with Vault.

- **vault-test-eso.sh**:
Utilized during the 'helm test' run, this script creates a temporary value in Vault to verify the correct configuration.
The ClusterSecretStore and ExternalSecrets should fetch this value to create a temporary Kubernetes secret.

Jobs and the majority of RBAC manifests are managed as Helm hooks, meaning they will be deleted post-execution.
Only the secret containing Vault initialization tokens (vault-init-secrets) and the service account for ESO will remain for future use.
Please be aware that this secret will not be automatically deleted or rewritten upon release removal; manual rotation and security measures must be enforced.


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
helm test vault -n vault-system
```
