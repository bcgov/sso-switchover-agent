#!/bin/bash
set -e

usage() {
    cat <<EOF
Test Disaster Recovery GitHub Actions workflows as a whole and ensure the data integrity.

Steps:
    1. trigger 'deploy.yml' workflow.
    2. create a set of test Keycloak realms via Gold Keycloak API.
    3. trigger 'switch-to-golddr.yml' workflow.
    4. ensure test Keycloak realms created by Gold Keycloak are found in Golddr Keycloak.
    5. create a set of test Keycloak realms via Golddr Keycloak API.
    6. trigger 'switch-to-gold.yml' workflow.
    7. ensure test Keycloak realms created by Golddr Keycloak are found in Gold Keycloak.

Usages:
    $0 <gh_token> <namespace>

Available namespaces:
    - c6af30-dev
    - c6af30-test
    - c6af30-prod

Examples:
    $ $0 ghp_xxxx c6af30-dev
EOF
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

gh_token=$1
namespace=$2

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

if [ "$(get_ocp_plate "$namespace")" != "c6af30" ]; then
    error "must run test scripts in sandbox environments"
    exit 1
fi

TEST_REALM_PREFIX="test-realm"

declare -a realms_gold=()
declare -a realms_golddr=()

i=0
while [ $i -ne 5 ]; do
    i=$((i + 1))
    realms_gold+=("$TEST_REALM_PREFIX-$i")
done

while [ $i -ne 5 ]; do
    i=$((i + 1))
    realms_golddr+=("$TEST_REALM_PREFIX-$i")
done

trigger_github_dispatcher "$gh_token" "deploy.yml" "$namespace" 300

ensure_kube_context "gold"
wait_for_keycloak_healthy "gold" "$namespace"

remove_all_realms "gold" "$namespace"

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
