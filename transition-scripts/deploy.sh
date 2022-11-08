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
    - c6af30-test
    - c6af30-prod
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
purge="false"

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

while [[ "$2" =~ ^- && ! "$2" == "--" ]]; do
    case $2 in
    -p | --purge)
        purge="true"
        ;;
    esac
    shift
done

# Gold deployments
switch_kube_context "gold" "$namespace"
check_ocp_cluster "gold"

helm_released=$(check_helm_release "$namespace" "sso-keycloak")
if [ "$helm_released" == "found" ]; then
    if [ "$purge" == "true" ]; then
        uninstall_helm "$namespace"
        cleanup_namespace "$namespace"
    else
        set_patroni_cluster_active "$namespace"
    fi
fi

upgrade_helm_active "$namespace"

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"

# Golddr deployments
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

upgrade_helm_standby "$namespace"

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"
wait_for_patroni_xlog_synced "$namespace"
