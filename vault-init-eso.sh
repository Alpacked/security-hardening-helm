#!/bin/sh

enable_eso() {
    local eso_service_account_namespace
    local eso_service_account_name
    local eso_pod_name

    export SA_JWT_TOKEN=$(kubectl -n vault get secret auth-sa-token -o jsonpath="{.data.token}" | base64 --decode; echo)
    export SA_CA_CRT=$(kubectl -n external-secrets get secret auth-sa-token -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

    kubectl exec vault-0 -n vault -- vault auth enable kubernetes

    kubectl exec vault-0 -n vault -- vault write auth/kubernetes/config \
    token_reviewer_jwt="$SA_JWT_TOKEN" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert="$SA_CA_CRT"

kubectl exec -i vault-0 -n vault -- sh -c 'cat <<EOF | vault policy write read-only -
path "kv/*" {
capabilities = ["read"]
}
EOF'

    kubectl exec vault-0 -n vault -- vault write auth/kubernetes/role/eso-reader \
            bound_service_account_names="auth-sa-eso" \
            bound_service_account_namespaces="external-secrets" \
            policies="read-only" \
            ttl=24h

    eso_pod_name=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=external-secrets -o=jsonpath='{.items[0].metadata.name}')
    eso_namespace=$(kubectl get pods --all-namespaces -l app.kubernetes.io/name=external-secrets -o=jsonpath='{.items[0].metadata.namespace}')

    kubectl label pods "$eso_pod_name" -n "$eso_namespace" initialize=true --overwrite

    kubectl exec vault-0 -n vault -- vault secrets enable -version=2 kv
    kubectl exec vault-0 -n vault -- vault kv put kv/test-secret test_user=success
}

if kubectl get pods --all-namespaces -l app.kubernetes.io/name=external-secrets 2>/dev/null | grep -qv 'No resources found'; then
  if kubectl get pods --all-namespaces -l app.kubernetes.io/name=external-secrets -l initialize=true 2>/dev/null | grep -qv 'No resources found'; then
    echo "ESO has already been initialized."
    exit 0
  else
    enable_eso
    exit 0
  fi
else
  echo "ESO does not exist"
  exit 0
fi