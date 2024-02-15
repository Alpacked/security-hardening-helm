# Helm Chart for Vault (and External Secrets) Automatic Deployment

![Version: 0.27.1](https://img.shields.io/badge/Version-0.27.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.15.2](https://img.shields.io/badge/AppVersion-1.15.2-informational?style=flat-square)
[![Docker Build and Scan Image](https://github.com/Alpacked/security-hardening-helm/actions/workflows/docker-build-scan.yaml/badge.svg)](https://github.com/Alpacked/security-hardening-helm/actions/workflows/docker-build-scan.yaml)
[![Release Charts](https://github.com/Alpacked/security-hardening-helm/actions/workflows/helm-release.yaml/badge.svg)](https://github.com/Alpacked/security-hardening-helm/actions/workflows/helm-release.yaml)

A Vault Helm chart for Kubernetes

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

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://helm.releases.hashicorp.com | vault | 0.27.x |

## Values

<table>
	<thead>
		<th>Key</th>
		<th>Type</th>
		<th>Default</th>
		<th>Description</th>
	</thead>
	<tbody>
		<tr>
			<td>esoInit.enabled</td>
			<td>bool</td>
			<td><pre lang="json">
false
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>esoInit.namespace</td>
			<td>string</td>
			<td><pre lang="json">
"external-secrets-system"
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>esoInit.serviceAccount.name</td>
			<td>string</td>
			<td><pre lang="json">
"auth-eso-init"
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>image.imagePullPolicy</td>
			<td>string</td>
			<td><pre lang="json">
"Always"
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>image.repository</td>
			<td>string</td>
			<td><pre lang="json">
"alpacked/vault-init-scripts"
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>image.tag</td>
			<td>string</td>
			<td><pre lang="json">
"0.1.1-rc"
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>vault.injector.enabled</td>
			<td>bool</td>
			<td><pre lang="json">
false
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>vault.server.ha.enabled</td>
			<td>bool</td>
			<td><pre lang="json">
false
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>vault.server.ha.raft.enabled</td>
			<td>bool</td>
			<td><pre lang="json">
false
</pre>
</td>
			<td></td>
		</tr>
		<tr>
			<td>vault.server.serviceAccount.createSecret</td>
			<td>bool</td>
			<td><pre lang="json">
true
</pre>
</td>
			<td></td>
		</tr>
	</tbody>
</table>

----------------------------------------------
Autogenerated from chart metadata using [helm-docs](https://github.com/norwoodj/helm-docs) and [README.md.gotmpl](README.md.gotmpl)
