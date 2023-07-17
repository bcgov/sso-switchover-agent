#!/bin/bash
set -e

usage() {
    cat <<EOF
Destroy Keycloak resources in the target namespaces.

Usages:
    $0 <namespace> [-p|--purge]

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod

Examples:
    $ $0 e4ca1d-dev
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

if [ "$(get_ocp_plate "$namespace")" != "e4ca1d" ]; then
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
