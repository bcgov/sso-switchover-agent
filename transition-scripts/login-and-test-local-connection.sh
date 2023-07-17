#!/bin/bash
set -e

usage() {
    cat <<EOF
This logs into both Gold and GoldDr clusters, then tests that the cluster switching
works properly by checking the patroni health in the two clusters. Used for running
transition scripts from local terminal. The namespace argument determines which
namespace the script uses for it's health check.


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
    - the terminal must be logged into the service account.

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

set -o allexport
source .env
set +o allexport
oc login --token="$GOLD_TOKEN" --server=https://api.gold.devops.gov.bc.ca:6443
oc login --token="$GOLDDR_TOKEN" --server=https://api.golddr.devops.gov.bc.ca:6443

# Golddr status check
switch_kube_context "golddr" "$namespace"

patroni_health=$(check_patroni_health "$namespace")
info "The patroni gold dr health is: $patroni_health"
if [ "$patroni_health" != "up" ]; then
    warn "the patroni pods are not healthy in Golddr"
fi


# Gold status check
switch_kube_context "gold" "$namespace"

patroni_health=$(check_patroni_health "$namespace")

info "The patroni gold health is: $patroni_health"
if [ "$patroni_health" != "up" ]; then
    warn "the patroni pods are not healthy in Gold"
fi

# Golddr deployments
switch_kube_context "golddr" "$namespace"

patroni_health=$(check_patroni_health "$namespace")

info "The patroni golddr health is: $patroni_health"
if [ "$patroni_health" != "up" ]; then
    warn "the patroni pods are not healthy in Gold"
fi
