#!/bin/sh

API_SERVER="https://kubernetes.default.svc"
SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
SA_NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"

get_vault_root_token() {
  echo "Getting Vault root token from \"vault-init-secrets\" for future requests..."

  local secret_manifest=$(curl -s -k -X GET \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Accept: application/json" \
      "${API_SERVER}/api/v1/namespaces/${VAULT_NAMESPACE}/secrets/vault-init-secrets")

  VAULT_ROOT_TOKEN=$(echo "${secret_manifest}" | jq -r '.data.root_token' | base64 -d)
}

enable_k8s_auth() {
  echo "Enabling K8S auth in Vault..."

  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data "{\"type\": \"kubernetes\"}" \
      "${VAULT_ADDRESS}/v1/sys/auth/kubernetes"

  curl -X POST \
     --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
     --data "{\"kubernetes_host\": \"https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}\"}" \
     "${VAULT_ADDRESS}/v1/auth/kubernetes/config"
}

enable_kv2_engine() {
  echo "Enabling Key-Value engine..."

  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data "{\"type\": \"kv\", \"options\": {\"version\": \"2\"}}" \
      "${VAULT_ADDRESS}/v1/sys/mounts/kv"
}

write_eso_permissions() {
  echo "Adding read-only permissions to External Secrets in Vault..."

  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data '{"policy": "path \"kv/data/*\" { capabilities = [\"read\"] }"}' \
      "${VAULT_ADDRESS}/v1/sys/policies/acl/read-only"

  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data '{
        "bound_service_account_names": "auth-eso-init",
        "bound_service_account_namespaces": "${SA_NAMESPACE}",
        "policies": "read-only",
        "ttl": "24h"
      }' \
      "${VAULT_ADDRESS}/v1/auth/kubernetes/role/eso-reader"
}

get_vault_root_token
enable_k8s_auth
enable_kv2_engine
write_eso_permissions

echo "Done."
