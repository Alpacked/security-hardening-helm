#!/bin/sh

API_SERVER="https://kubernetes.default.svc"
SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
SA_NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
SA_CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

get_secret_from_k8s() {
  curl -s -X GET \
    --cacert "${SA_CACERT}" \
    -H "Authorization: Bearer ${SA_TOKEN}" \
    -H "Accept: application/json" \
    "${API_SERVER}/api/v1/namespaces/${2}/secrets/${1}"
}

create_test_secret() {
  curl -X POST \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      --data "{\"data\": {\"test-user\": \"success\"}}" \
      "${VAULT_ADDRESS}/v1/kv/data/test-secret"
}

destroy_test_secret() {
  curl -X DELETE \
      --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      "${VAULT_ADDRESS}/v1/kv/data/test-secret"
}

echo "Getting Vault root token from \"${VAULT_SECRET_NAME}\" for future requests..."
VAULT_ROOT_TOKEN=$(get_secret_from_k8s $VAULT_SECRET_NAME $VAULT_NAMESPACE | jq -r '.data.root_token' | base64 -d)

echo "Creating test secret..."
create_test_secret

for i in $(seq 1 10); do
    echo "Trying to get desired value from k8s secret..."
    secret_value=$(get_secret_from_k8s $TEST_SECRET_NAME $SA_NAMESPACE | awk -F'"' '/"test-user":/{print $(NF-1)}' | base64 -d)

    if [ "$secret_value" == "success" ]; then
        echo "Success on attempt №$i. Removing test secret from Vault..."
        destroy_test_secret
        echo "Done."

        exit 0
    else
        echo "Attempt №$i failed. Retrying in 10 seconds..."
    fi
    sleep 10
done

echo "Attempt limit reached. Removing test secret from Vault..."
destroy_test_secret
echo "Done."

exit 1
