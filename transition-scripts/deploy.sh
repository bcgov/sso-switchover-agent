#!/bin/bash
set -e

usage() {
    cat <<EOF
Deploy Keycloak resources in the target namespaces in a normal situation;
it sets "active" mode in Gold cluster and "standby" mode in Golddr cluster.

Usages:
    $0 <namespace>

Available namespaces:
    - c6af30-dev
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Examples:
    $ $0 c6af30-dev
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

namespace=$1

pwd="$(dirname "$0")"
source "$pwd/helpers.sh"

switch_kube_context "gold" "$namespace"
check_ocp_cluster "gold"

uninstall_helm "$namespace"
cleanup_namespace "$namespace"

upgrade_helm_active "$namespace"

switch_kube_context "golddr" "$namespace"
check_ocp_cluster "golddr"

uninstall_helm "$namespace"
cleanup_namespace "$namespace"

upgrade_helm_standby "$namespace"
