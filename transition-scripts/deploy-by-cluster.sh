#!/bin/bash
set -e

usage() {
    cat <<EOF
Deploy Keycloak resources in the target namespaces in a normal situation;
it sets "active" mode in Gold cluster and "standby" mode in Golddr cluster.

Usages:
    $0 <namespace> <cluster>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Examples:
    $ $0 e4ca1d-dev gold
EOF
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

namespace=$1
cluster=$2

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"


# Cluster deployments
switch_kube_context "$cluster" "$namespace"
check_ocp_cluster "$cluster"

helm_released=$(check_helm_release "$namespace" "sso-keycloak")
if [ "$helm_released" == "found" ]; then
    set_patroni_cluster_active "$namespace"
fi

upgrade_helm_active "$namespace"

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"
