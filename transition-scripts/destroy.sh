#!/bin/bash
set -e

usage() {
    cat <<EOF
Destroy Keycloak resources in the target namespaces.

Usages:
    $0 <namespace> [-p|--purge]

Available namespaces:
    - c6af30-dev
    - c6af30-test
    - c6af30-prod

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

if [ "$(get_ocp_plate "$namespace")" != "c6af30" ]; then
    error "must run test scripts in sandbox environments for now"
    exit 1
fi

while [[ "$2" =~ ^- && ! "$2" == "--" ]]; do
    case $2 in
    -p | --purge)
        purge="true"
        ;;
    esac
    shift
done

switch_kube_context "gold" "$namespace"
uninstall_helm "$namespace"

if [ "$purge" == "true" ]; then
    cleanup_namespace "$namespace"
fi

switch_kube_context "golddr" "$namespace"
uninstall_helm "$namespace"

if [ "$purge" == "true" ]; then
    cleanup_namespace "$namespace"
fi
