#!/bin/bash
set -e

usage() {
    cat <<EOF
Enable or disable the gold vanity route, forcing the GSLB health check to fail.

Usages:
    $0 <namespace> <enable_state>

Available namespaces:
    - c6af30-dev
    - c6af30-test
    - c6af30-prod
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

KEYCLOAK_ROUTE=$(get_vanity_route_name "$namespace")

switch_kube_context "gold" "$namespace"

if [ "$action" = "disable" ]
then
    kubectl -n "$namespace" get route "$KEYCLOAK_ROUTE" -p '{"spec":{"to":{"name":"sso-keycloak-disabled"}}}'
elif [ "$action" = "enable" ]
then
    kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p '{"spec":{"to":{"name":"sso-keycloak"}}}'
fi
