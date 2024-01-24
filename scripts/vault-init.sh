#!/bin/sh

API_SERVER="https://kubernetes.default.svc"
SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
SA_NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
LEADER_VAULT_ADDRESS="http://vault-0.vault-internal.${SA_NAMESPACE}:8200"
LEADER_SECRET_THRESHOLD=3
LEADER_SECRET_SHARES=5

get_vault_pod_list() {
  curl -k -X GET \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Accept: application/json" \
      "${API_SERVER}/api/v1/namespaces/${SA_NAMESPACE}/pods?labelSelector=component%3Dserver" | jq -r '.items[].metadata.name'
}

save_secrets() {
  local count=0
  local unseal_tokens="{}"

  while read -r token; do
    count=$((count+1))
    token=$(echo -n "$token" | base64 -w 0)
    unseal_tokens=$(echo "$unseal_tokens" | jq --arg count "$count" --arg token "$token" '. + {("unseal_token_" + $count): $token}')
  done < <(echo "${LEADER_RESPONSE}" | jq -r '.keys[]')

  local json_payload=$(jq -n \
    --argjson unsealTokens "${unseal_tokens}" \
    --arg rootToken "$(echo -n "${LEADER_RESPONSE}" | jq -rj ".root_token" | base64 -w 0)" \
    --arg namespace "${SA_NAMESPACE}" \
    '{
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
          "name": "vault-init-secrets",
          "namespace": $namespace
        },
        "type": "Opaque",
        "data": ({"root_token": $rootToken} + $unsealTokens)
      }'
  )

  curl -s -k -X POST \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${json_payload}" \
      "${API_SERVER}/api/v1/namespaces/${SA_NAMESPACE}/secrets"

  echo "Saving tokens to vault-init-secrets..."
}

initialize_vault() {
  LEADER_RESPONSE=$(curl -s -X POST \
                        --data "{\"secret_shares\": ${LEADER_SECRET_SHARES}, \"secret_threshold\": ${LEADER_SECRET_THRESHOLD}}" \
                        "${LEADER_VAULT_ADDRESS}/v1/sys/init")

  if [ "$(curl -s "${LEADER_VAULT_ADDRESS}/v1/sys/health" | jq -r '.initialized')" = "true" ]; then
      echo "Vault is initialized."
      save_secrets
  else
      echo "Vault is not initialized."
      exit 1
  fi

  echo "Trying to unseal the Vault..."
  for i in $(seq 0 $((LEADER_SECRET_THRESHOLD - 1))); do
      local unseal_key=$(echo "$LEADER_RESPONSE" | jq -r ".keys[$i]")
      local unseal_response=$(curl -s -X POST \
                                --data "{\"key\": \"$unseal_key\"}" \
                                "${LEADER_VAULT_ADDRESS}/v1/sys/unseal")
      echo "Keys applied: $((i+1))"
      sleep 1 # Waiting to prevent spam
  done

  if [ "$(curl -s "${LEADER_VAULT_ADDRESS}/v1/sys/health" | jq -r '.sealed')" = "false" ]; then
    echo "Vault is unsealed."
  else
      echo "Vault is still sealed."
      exit 1
  fi
}

initialize_raft_vault() {
  local pod_name="$1"
  local raft_vault_address="http://${pod_name}.vault-internal.${SA_NAMESPACE}:8200"

  local raft_response=$(curl -s -X POST \
                        --header "X-Vault-Token: $(echo "${LEADER_RESPONSE}" | jq -rj ".root_token")" \
                        --data "{\"leader_api_addr\": \"${LEADER_VAULT_ADDRESS}\"}" \
                        "${raft_vault_address}/v1/sys/storage/raft/join")

  if [ "$(curl -s "${raft_vault_address}/v1/sys/health" | jq -r '.initialized')" = "true" ]; then
      echo "Raft $pod_name is initialized. Waiting 5 seconds to estabilish connection with master node..."
      sleep 5
  else
      echo "Raft $pod_name is not initialized."
      exit 1
  fi

  echo "Trying to unseal the raft $pod_name..."
  for i in $(seq 0 $((LEADER_SECRET_THRESHOLD - 1))); do
      local unseal_key=$(echo "$LEADER_RESPONSE" | jq -r ".keys[$i]")
      local unseal_response=$(curl -s -X POST \
                                --data "{\"key\": \"$unseal_key\"}" \
                                "${raft_vault_address}/v1/sys/unseal")
      echo "Keys applied: $((i+1))"
      sleep 1 # Waiting to prevent spam
  done

  if [ "$(curl -s "${raft_vault_address}/v1/sys/health" | jq -r '.sealed')" = "false" ]; then
    echo "Raft $pod_name is unsealed."
  else
      echo "Raft $pod_name is still sealed."
      exit 1
  fi
}

vault_pod_list=$(get_vault_pod_list)
for pod in $vault_pod_list; do
  if [ "$pod" == "vault-0" ]; then
      initialize_vault
  else
      initialize_raft_vault $pod
  fi
done
