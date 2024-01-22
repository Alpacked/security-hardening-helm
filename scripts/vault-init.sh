#!/bin/sh

API_SERVER="https://kubernetes.default.svc"
SA_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
SA_NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
LEADER_VAULT_ADDRESS="http://vault-0.vault-internal.${SA_NAMESPACE}:8200"

get_vault_pod_list() {
  curl -k -X GET \
      -H "Authorization: Bearer $SA_TOKEN" \
      -H "Accept: application/json" \
      "$APISERVER/api/v1/namespaces/$SA_NAMESPACE/pods" | jq -r '.items[].metadata.name | select(test("vault-agent-injector") == false)'
}

save_secrets() {
  local unseal_tokens=""

  for i in $(seq 0 $(($(echo "$LEADER_RESPONSE" | jq -r '.keys_base64 | length') - 1))); do
    count=$((i+1))
    unseal_tokens+="\"unseal_token_$count\": \"$(echo "$LEADER_RESPONSE" | jq -r ".keys_base64[$i]")\""
    if [ $i -lt $(($(echo "$LEADER_RESPONSE" | jq -r '.keys_base64 | length') - 1)) ]; then
      unseal_tokens+=", "
    fi
  done

  curl -k -X POST \
      -H "Authorization: Bearer $SA_TOKEN" \
      -H "Content-Type: application/json" \
      --data '{
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
          "name": "vault-init-secrets",
          "namespace": "'"$SA_NAMESPACE"'"
        },
        "type": "Opaque",
        "data": {
          "root_token": "'"$(echo "$LEADER_RESPONSE" | jq -r ".root_token" | base64 -w 0)"'",
          '"$unseal_tokens"'
        }
      }' \
      "$API_SERVER/api/v1/namespaces/$SA_NAMESPACE/secrets"
}

initialize_vault() {
  local vault_secret_threshold=3
  local vault_secret_shares=5

  LEADER_RESPONSE=$(curl -s -X POST \
                        --data "{\"secret_shares\": ${vault_secret_shares}, \"secret_threshold\": ${vault_secret_threshold}}" \
                        "${LEADER_VAULT_ADDRESS}/v1/sys/init")

  if [ "$(curl -s "${LEADER_VAULT_ADDRESS}/v1/sys/health" | jq -r '.initialized')" = "true" ]; then
      echo "Vault is initialized."
      save_secrets
  else
      echo "Vault is not initialized."
      exit 1
  fi

  echo "Trying to unseal the Vault..."
  for i in $(seq 0 $((vault_secret_threshold - 1))); do
      local unseal_key=$(echo "$LEADER_RESPONSE" | jq -r ".keys[$i]")
      local unseal_response=$(curl -s -X POST \
                                --data "{\"key\": \"$unseal_key\"}" \
                                "${LEADER_VAULT_ADDRESS}/v1/sys/unseal")
      echo "Keys applied: $((i+1))"
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
                        --header "X-Vault-Token: $(echo "$LEADER_RESPONSE" | jq -r ".root_token")" \
                        --data "{\"leader_api_addr\": ${LEADER_VAULT_ADDRESS}}" \
                        "${raft_vault_address}/v1/sys/storage/raft/join")

  if [ "$(curl -s "${raft_vault_address}/v1/sys/health" | jq -r '.initialized')" = "true" ]; then
      echo "Raft Vault $pod_name is initialized."
  else
      echo "Raft Vault $pod_name is not initialized."
      exit 1
  fi

  echo "Trying to unseal the $pod_name raft Vault..."
  for i in $(seq 0 $((vault_secret_threshold - 1))); do
      local unseal_key=$(echo "$LEADER_RESPONSE" | jq -r ".keys[$i]")
      local unseal_response=$(curl -s -X POST \
                                --data "{\"key\": \"$unseal_key\"}" \
                                "${raft_vault_address}/v1/sys/unseal")
      echo "Keys applied: $((i+1))"
  done

  if [ "$(curl -s "${raft_vault_address}/v1/sys/health" | jq -r '.sealed')" = "false" ]; then
    echo "Raft Vault $pod_name is unsealed."
  else
      echo "Raft Vault $pod_name is still sealed."
      exit 1
  fi
}

vault_pod_list=$(get_vault_pod_list)
for pod in $pod_list; do
  if [ "$pod" == "vault-0" ]; then
      initialize_vault
  elif
      initialize_raft_vault $pod
  fi
done
