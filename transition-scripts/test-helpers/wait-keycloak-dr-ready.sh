#!/bin/bash
set -e

usage() {
    cat <<EOF
Waits for keycloak DR to be ready Used for test automation.
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

namespace=$1

pwd="$(dirname "$0")"
source "$pwd/../helpers/_all.sh"

# Golddr deployments
echo "Ensure cluster is golddr."

switch_kube_context "golddr"
ensure_kube_context "golddr"

wait_for_keycloak_all_ready "$namespace"

info "Keycloak pods are ready in $namespace"


count=0
wait_ready() {
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

while wait_ready; do sleep 5; done
