#!/bin/sh

echo "Waiting for 20 seconds before starting the script..."
sleep 20

get_vault_namespace() {
  local vault_namespace
  vault_namespace=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=vault -o=jsonpath='{.items[0].metadata.namespace}')
  echo "$vault_namespace"
}

initialize_vault() {
  local namespace="$1"
  local vault_status
  local vault_root_token
  vault_status=$(kubectl exec vault-0 -n "$namespace" -- vault status -format=json)

  echo "Initializing Vault in namespace: $namespace"

  kubectl exec vault-0 -n "$namespace" -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json

  local vault_initialized
  vault_initialized=$(echo "$vault_status" | jq -r .initialized)

  local unseal_key
  unseal_key=$(cat cluster-keys.json | jq -r ".unseal_keys_b64[]")

  kubectl exec vault-0 -n "$namespace" -- vault operator unseal "$unseal_key" > /dev/null 2>&1

  local vault_sealed
  vault_sealed=$(echo "$vault_status" | jq -r .sealed)
  sleep 10

  vault_root_token=$(cat cluster-keys.json | jq -r ".root_token")
  kubectl exec vault-0 -n "$namespace" -- vault login "$vault_root_token" > /dev/null 2>&1
  kubectl create secret -n "$namespace" generic vault-root-token --from-literal=token="$vault_root_token"

  if [ "$vault_initialized" = "true" ] && [ "$vault_sealed" = "false" ]; then
    echo "The Vault server is initialized and unsealed."
    return 0
  fi
}

get_vault_pods() {
  local namespace="$1"
  kubectl get pods -n vault -o json | jq -r '.items[].metadata.name | select(. != "vault-0" and test("vault-agent-injector") == false)'
}

join_another_pods() {
  local namespace="$1"
  local pod="$2"
  local unseal_key

  unseal_key=$(cat cluster-keys.json | jq -r ".unseal_keys_b64[]")

  kubectl exec $pod -n "$namespace" -- vault operator raft join http://vault-0.vault-internal:8200
  kubectl exec $pod -n "$namespace" -- vault operator unseal "$unseal_key" > /dev/null 2>&1
}

VAULT_NAMESPACE=$(get_vault_namespace)

if [ -z "$VAULT_NAMESPACE" ]; then
  echo "Error: No 'vault' found."
  exit 1
fi

echo "Namespace for 'vault' release: $VAULT_NAMESPACE"

initialize_vault "$VAULT_NAMESPACE"

VAULT_PODS=($(get_vault_pods "$VAULT_NAMESPACE"))

if [ ${#VAULT_PODS[@]} -eq 0 ]; then
  echo "No eligible Vault pods found."
  exit 0
else
  for VAULT_POD in "${VAULT_PODS[@]}"; do
    join_another_pods "$VAULT_NAMESPACE" "$VAULT_POD"
    sleep 10
  done
fi
