#!/bin/bash
set -e

usage() {
    cat <<EOF
Set the target namespace of the Golddr cluster active, and the corresponding Gold cluster standby.

Steps:
    1. check if the patroni cluster in Golddr is running as 'standby mode'.
    2. convert the patroni cluster in Golddr to an 'active mode'.
    3. scale up the Keycloak deployment and update the DB endpoint to Golddr.
    4. set the route endpoint to the maintenance page in Golddr.
    5. set the route endpoint to the Keycloak when Keycloak & Patroni pods are ready in Golddr.
    6. convert the patroni cluster in Gold to an 'standby mode'.
    7. scale down the Keycloak deployment in Gold.

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
    - the patroni cluster in Gold must be healthy and in active mode for this to complete successfully.
      However the switchover to gold dr will still occur if gold is down.
    - the patroni cluster in Golddr must be healthy and in standby mode.

Examples:
    $ $0 e4ca1d-dev

Notes:
    - active Keycloak pods must be re-created because Keycloak caches realms & users' info in the memory.

Considerations:
    - should we re-create Keycloak pods each time or clear the cache to fetch the new data.
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
echo "Ensure cluster is golddr."
ensure_kube_context "golddr"

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

info "enabling maintenance page in $namespace"
upgrade_helm_active "$namespace" --maintenance-on
wait_for_keycloak_all_ready "$namespace"

info "Keycloak pods are ready in $namespace"
upgrade_helm_active "$namespace"

# Gold deployments
switch_kube_context "gold" "$namespace"

cluster_update=$(set_patroni_cluster_standby "$namespace")
if [ "$cluster_update" != "success" ]; then
    error "failed to convert patroni cluster type to standby"
    exit 1
fi

upgrade_helm_standby "$namespace"

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"
wait_for_patroni_xlog_synced "$namespace"
