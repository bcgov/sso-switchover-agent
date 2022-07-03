#!/bin/bash
set -e

usage() {
    cat <<EOF
Test Disaster Recovery GitHub Actions workflows as a whole and ensure the data integrity.

Steps:
    1. trigger 'deploy.yml' workflow.
    2. trigger 'switch-to-golddr.yml' workflow.
    3. trigger 'switch-to-gold.yml' workflow.

Usages:
    $0 <namespace>

Available namespaces:
    - c6af30-dev

Examples:
    $ $0 c6af30-dev
EOF
}

if [ "$#" -lt 3 ]; then
    usage
    exit 1
fi

gh_token=$1
namespace=$2
realm_prefix=$3

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

declare -a realms_gold=("$realm_prefix-1" "$realm_prefix-2" "$realm_prefix-3")
declare -a realms_golddr=("$realm_prefix-4" "$realm_prefix-5" "$realm_prefix-6")

trigger_github_dispatcher "$gh_token" "deploy.yml" "$namespace" 300

ensure_kube_context "gold"
wait_for_keycloak_healthy "gold" "$namespace"

for realm in "${realms_gold[@]}"; do
    create_keycloak_realm "gold" "$namespace" "$realm"
done

trigger_github_dispatcher "$gh_token" "switch-to-golddr.yml" "$namespace" 900

ensure_kube_context "golddr"
wait_for_keycloak_healthy "golddr" "$namespace"

for realm in "${realms_gold[@]}"; do
    info "checking realm $realm..."
    data=$(get_keycloak_realm "golddr" "$namespace" "$realm")
    if [ -z "$data" ]; then
        echo "$data"
        exit 1
    fi
done

for realm in "${realms_golddr[@]}"; do
    create_keycloak_realm "golddr" "$namespace" "$realm"
done

trigger_github_dispatcher "$gh_token" "switch-to-gold.yml" "$namespace" 900

ensure_kube_context "gold"
wait_for_keycloak_healthy "gold" "$namespace"

for realm in "${realms_golddr[@]}"; do
    info "checking realm $realm..."
    data=$(get_keycloak_realm "gold" "$namespace" "$realm")
    if [ -z "$data" ]; then
        echo "$data"
        exit 1
    fi
done

info "done"
