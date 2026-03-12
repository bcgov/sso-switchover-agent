#!/bin/bash
set -e

usage() {
    cat <<EOF
Deploy Keycloak resources in the target namespaces in gold without changing
the service the vanity route is pointing to.  This is used when re-deploying gold
WITHOUT interupting traffic to GoldDR

Usages:
    $0 <namespace>

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
cluster="gold"

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

### TODO CREATE A CHECK THAT ENSURES TRAFFIC IS GOING TO GOLDDR



# Cluster deployments
# switch_kube_context "$cluster" "$namespace"
check_ocp_cluster "$cluster"

helm_released=$(check_helm_release "$namespace" "sso-keycloak")
if [ "$helm_released" == "found" ]; then
    set_patroni_cluster_active "$namespace"
fi

# upgrade_helm_active "$namespace"
upgrade_helm "$namespace" "active" \
--set maintenancePage.enabled="false" \
--set maintenancePage.active="false"

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"
