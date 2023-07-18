#!/bin/bash
set -e

usage() {
    cat <<EOF
Deploy Keycloak resources in the target Gold namespaces in standby mode.
This is for use in the case that gold was not able to be put into standby mode.
The user will have to scale Patroni-Gold pods to zero before running. This script will
delete existing patroni PVCs and configmaps.

Usages:
    $0 <namespace>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Pre-conditions:
    - the patroni cluster in Golddr must be healthy and in active mode.
    - the Gold patroni pods are scaled to zero.

Examples:
    $ $0 e4ca1d-dev
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

namespace=$1

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

# Ensure Gold DR is healthy and active
switch_kube_context "golddr" "$namespace"
check_ocp_cluster "golddr"

wait_for_patroni_healthy "$namespace"
patroni_mode=$(check_patroni_cluster_mode "$namespace")

if [ "$patroni_mode" == "active" ]; then
    echo "Patroni DR in active mode"
else
    echo "Patroni DR not in active mode"
    exit 1
fi


# Gold deployments
switch_kube_context "gold" "$namespace"
check_ocp_cluster "gold"

cleanup_namespace "$namespace"

info "Cleaned up the pvcs"
upgrade_helm_standby "$namespace"

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"
