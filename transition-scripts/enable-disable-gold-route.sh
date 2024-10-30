#!/bin/bash
set -e

usage() {
    cat <<EOF
Enable or disable the gold vanity route, forcing the GSLB health check to fail.

Usages:
    $0 <namespace> <enable_state>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

EOF
}

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

if [ "$#" -lt 2 ]; then exit 1; fi

namespace="$1"
action="$2"

echo "THIS IS STEP 2"
KEYCLOAK_ROUTE=$(get_vanity_route_name "$namespace")
echo "THIS IS STEP 3"
switch_kube_context "gold" "$namespace"

if [ "$action" = "disable" ]
then
    kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p '{"spec":{"to":{"name":"sso-keycloak-disabled"}}}'
elif [ "$action" = "enable" ]
then
    echo "THIS IS STEP 4"
    kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p '{"spec":{"to":{"name":"sso-keycloak"}}}'
fi
