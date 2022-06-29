#!/bin/bash
set -e

usage() {
    cat <<EOF
Set the target namespace of the Golddr cluster active, and the corresponding Gold cluster standby.

Steps:
    1. check if the patroni cluster in Golddr is running as 'standby mode'.
    2. convert the patroni cluster in Golddr to an 'active mode'.
    3. scale up the Keycloak deployment and update the DB endpoint to Golddr.
    4. wait until all Keycloak pods are running and healthy in Golddr.
    5. convert the patroni cluster in Gold to an 'standby mode'.
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

Notes:
    - active Keycloak pods must be re-created because Keycloak caches realms & clients' info in the memory.
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

namespace=$1

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

# Golddr deployments
switch_kube_context "golddr" "$namespace"
check_ocp_cluster "golddr"

patroni_mode=$(check_patroni_cluster_mode "$namespace")
if [ "$patroni_mode" != "standby" ]; then
    error "the patroni pods are not running in standby mode ($patroni_mode)"
    exit 1
fi

info "starting to convert patroni cluster type to active in $namespace"

cluster_update=$(set_patroni_cluster_active "$namespace")
if [ "$cluster_update" != "success" ]; then
    error "failed to convert patroni cluster type to active"
    exit 1
fi

patroni_mode=$(check_patroni_cluster_mode "$namespace")
if [ "$patroni_mode" != "active" ]; then
    error "the patroni pods are not running in active mode ($patroni_mode)"
    exit 1
fi

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"

upgrade_helm_active "$namespace"
wait_for_keycloak_all_ready "$namespace"

# Gold deployments
switch_kube_context "gold" "$namespace"
check_ocp_cluster "gold"

cluster_update=$(set_patroni_cluster_standby "$namespace")
if [ "$cluster_update" != "success" ]; then
    error "failed to convert patroni cluster type to standby"
    exit 1
fi

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"

upgrade_helm_standby "$namespace"
