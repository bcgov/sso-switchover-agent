#!/bin/bash
set -e

usage() {
    cat <<EOF
Waits for keycloak DR to be ready. Used for test automation.
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

namespace=$1

pwd="$(dirname "$0")"
source "$pwd/../helpers/_all.sh"

wait_for_keycloak_all_ready_with_replicas() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  count_kc=0
  wait_kc_ready() {
    replicas=$(kubectl get deployment sso-keycloak -n "$namespace" -o jsonpath='{.spec.replicas}')
    ready_count=$(count_ready_keycloak_pods "$namespace")
    info "keycloak ready $ready_count/$replicas"

    if [ "$replicas" -gt 0 ] && [ "$ready_count" == "$replicas" ]; then return 1; fi

    # wait for 30mins
    if [[ "$count_kc" -gt 360 ]]; then
      warn "keycloak replicas is not ready"
      exit 1
    fi

    count_kc=$((count_kc + 1))
  }

  while wait_kc_ready; do sleep 5; done
}


# Golddr deployments
echo "Ensure cluster is golddr."

switch_kube_context "golddr"
ensure_kube_context "golddr"

echo "Wait for keycloak DR pods to be up and for the replica count to be greater than zero.
This will only pass after the 'Set DR active' action has run successfully"

wait_for_keycloak_all_ready_with_replicas "$namespace"

info "Keycloak pods are ready in $namespace"






count=0
wait_for_route_to_direct_to_keycloak() {
    routeservicename=$(oc -n "$namespace" get route sso-keycloak -o jsonpath='{.spec.to.name}')
    info "The route is directing traffic to the $routeservicename service."

    if [ "$routeservicename" == "sso-keycloak" ]; then
        echo "The keycloak dr service is up, failover successful"
        return 1
    else
        error "The keycloak service is not up yet"
    fi

# wait for up to 20mins
if [[ "$count" -gt 240 ]]; then
    warn "The failover was unsuccessful."
    exit 1
fi

count=$((count + 1))
}

while wait_for_route_to_direct_to_keycloak; do sleep 5; done
