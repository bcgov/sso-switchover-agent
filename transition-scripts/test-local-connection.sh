#!/bin/bash
set -e

usage() {
    cat <<EOF
This checks if the local environment allows the transition scripts to change contexts between the
Gold and GoldDR clusters.

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
    - the terminal must be logged into the service account.

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
