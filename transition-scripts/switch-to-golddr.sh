#!/bin/bash
set -e

usage() {
    cat <<EOF
Set the target namespace of the Golddr cluster active, and the corresponding Gold cluster standby.

Steps:
    1. check if the patroni cluster in Golddr is running as 'standby mode'.
    2. convert the patroni cluster in Golddr to an 'active mode'.
    3. scale up the Keycloak deployment and update the DB endpoint to Golddr.
    4. wait until all Keycloak pods are running and healthy.
    5. delete the patroni PVC in Gold.
    6. scale down the Keycloak deployment in Gold.

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
source "$pwd/helpers/_all.sh"

# Gold deployments
switch_kube_context "golddr" "$namespace"
check_ocp_cluster "golddr"

patroni_mode=$(check_patroni_cluster_mode "$namespace")
if [ "$patroni_mode" != "standby" ]; then
    error "the patroni pods are not running in standby mode ($patroni_mode)"
    exit 1
fi

info "starting to convert patroni cluster type to active in $namespace"

set_patroni_cluster_active "$namespace"
patroni_mode=$(check_patroni_cluster_mode "$namespace")
if [ "$patroni_mode" != "active" ]; then
    error "The current context ($(get_kube_context)) patroni pod is not in standby mode ($patroni_mode)"
    exit 1
fi

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"

upgrade_helm_active "$namespace"
wait_for_keycloak_all_ready "$namespace"

# Golddr deployments
switch_kube_context "gold" "$namespace"
check_ocp_cluster "gold"

set_patroni_cluster_standby "$namespace"
wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"

upgrade_helm_standby "$namespace"
