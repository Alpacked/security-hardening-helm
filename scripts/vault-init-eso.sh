#!/bin/sh

API_SERVER="https://kubernetes.default.svc"
SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
SA_NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
SA_CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

get_vault_root_token() {
  local secret_manifest=$(curl -s -X GET \
      --cacert "${SA_CACERT}" \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Accept: application/json" \
      "${API_SERVER}/api/v1/namespaces/${VAULT_NAMESPACE}/secrets/vault-init-secrets")

  VAULT_ROOT_TOKEN=$(echo "${secret_manifest}" | jq -r '.data.root_token' | base64 -d)
}

request_to_vault_api() {
  curl -X POST \
    --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
    --data "${2}" \
    "${VAULT_ADDRESS}${1}"
}

enable_k8s_auth() {
  request_to_vault_api "/v1/sys/auth/kubernetes" \
    "{
      \"type\": \"kubernetes\"
    }"

  request_to_vault_api "/v1/auth/kubernetes/config" \
    "{
      \"kubernetes_host\": \"https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}\"
    }"
}

enable_kv2_engine() {
  request_to_vault_api "/v1/sys/mounts/kv" \
    "{
      \"type\": \"kv\",
      \"options\": {
        \"version\": \"2\"
      }
    }"
}

write_eso_permissions() {
  request_to_vault_api "/v1/sys/policies/acl/read-only" \
    '{
      "policy": "path \"kv/data/*\" { capabilities = [\"read\"] }"
    }'

  request_to_vault_api "/v1/auth/kubernetes/role/eso-reader" \
    "{
      \"bound_service_account_names\": \"${ESO_SA}\",
      \"bound_service_account_namespaces\": \"${SA_NAMESPACE}\",
      \"policies\": \"read-only\",
      \"ttl\": \"24h\"
    }"
}

echo "Getting Vault root token from \"vault-init-secrets\" for future requests..."
get_vault_root_token

echo "Enabling K8S auth in Vault..."
enable_k8s_auth

echo "Enabling Key-Value engine..."
enable_kv2_engine

echo "Adding read-only permissions to External Secrets in Vault..."
write_eso_permissions

echo "Done."
