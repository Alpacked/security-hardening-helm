
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

create_test_secret() {
  echo "Creating test secret..."

  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data "{\"data\": {\"test-user\": \"success\"}}" \
      "${VAULT_ADDRESS}/v1/kv/data/test-secret"
}

destroy_test_secret() {
  echo "Cleaning test secret from Vault..."

  curl -X PUT \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data "{\"versions\": [0]" \
      "${VAULT_ADDRESS}/v1/kv/data/destroy/test-secret"
}

get_test_secret_value() {
  echo "Trying to get desired value from k8s secret..."

  local secret_manifest=$(curl -s -k -X GET \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Accept: application/json" \
      "${API_SERVER}/api/v1/namespaces/${SA_NAMESPACE}/secrets/${TEST_SECRET_NAME}")

  echo "${secret_manifest}" | jq -r '.data.test-user' | base64 -d
}

get_vault_root_token
create_test_secret

for i in $(seq 1 10); do
    if [ get_test_secret_value = "success" ]; then
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
