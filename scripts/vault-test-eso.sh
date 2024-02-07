#!/bin/sh

API_SERVER="https://kubernetes.default.svc"
SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
SA_NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
SA_CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

get_vault_root_token() {
  echo "Getting Vault root token from \"${VAULT_SECRET_NAME}\" for future requests..."

  local secret_manifest=$(curl -s -X GET \
      --cacert ${SA_CACERT} \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Accept: application/json" \
      "${API_SERVER}/api/v1/namespaces/${VAULT_NAMESPACE}/secrets/${VAULT_SECRET_NAME}")

  VAULT_ROOT_TOKEN=$(echo "${secret_manifest}" | jq -r '.data.root_token' | base64 -d)
}

create_test_secret() {
  echo "Creating test secret..."

  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data "{\"data\": {\"test-user\": \"success\"}}" \
      "${VAULT_ADDRESS}/v1/kv/data/test-secret"
}

destroy_test_secret() {
  echo "Delete test secret from Vault..."

  curl -X DELETE \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      "${VAULT_ADDRESS}/v1/kv/data/test-secret"
}

get_test_secret_value() {
  echo "Trying to get desired value from k8s secret..." >&2

  local secret_manifest=$(curl -s -X GET \
      --cacert ${SA_CACERT} \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Accept: application/json" \
      "${API_SERVER}/api/v1/namespaces/${SA_NAMESPACE}/secrets/${TEST_SECRET_NAME}")

  echo "${secret_manifest}" | awk -F'"' '/"test-user":/{print $(NF-1)}' | base64 -d
}

get_vault_root_token
create_test_secret

for i in $(seq 1 10); do
    secret_value=$(get_test_secret_value)
    if [ "$secret_value" == "success" ]; then
        echo "Success on attempt №$i."
        destroy_test_secret
        exit 0
    else
        echo "Attempt №$i failed. Retrying in 10 seconds..."
    fi
    sleep 10
done

destroy_test_secret
exit 1
