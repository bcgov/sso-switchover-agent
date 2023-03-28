#!/bin/bash
set -e

usage() {
    cat <<EOF
This deploys the dr resources in standby mode.
Adding the purge flag insures a clean install if xlog
synching is an issue.

Usages:
    $0 <namespace>

Available namespaces:
    - c6af30-dev
    - c6af30-test
    - c6af30-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Pre-conditions:
    - the patroni cluster in Gold must be healthy and in active mode.

Examples:
    $ $0 c6af30-dev false
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

namespace=$1
purge=$2

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

# Ensure Gold is healthy and active
switch_kube_context "gold" "$namespace"
check_ocp_cluster "gold"

wait_for_patroni_healthy "$namespace"
patroni_mode=$(check_patroni_cluster_mode "$namespace")

if [ "$patroni_mode" == "active" ]; then
    echo "Patroni-Gold in active mode"
else
    echo "Patroni-Gold not in active mode"
    exit 1
fi

# Golddr deployments (This is the same as the deploy block for DR)
switch_kube_context "golddr" "$namespace"
check_ocp_cluster "golddr"

helm_released=$(check_helm_release "$namespace" "sso-keycloak")
if [ "$helm_released" == "found" ]; then
    if [ "$purge" == "true" ]; then
        uninstall_helm "$namespace"
        cleanup_namespace "$namespace"
    else
        set_patroni_cluster_standby "$namespace"
    fi
fi

upgrade_helm_standby "$namespace" --maintenance-on

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"
wait_for_patroni_xlog_synced "$namespace"
