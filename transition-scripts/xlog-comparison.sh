#!/bin/bash
set -e

usage() {
    cat <<EOF
Compare the xlogs between patroni-gold and patroni-dr.  Alert team if they do not match.

Steps:
    1. Compare xlogs for different namespaces.
    2. If the job fails or xlog comparison is off, send rocketchat alert

Usages:
    $0

Available namespaces:
    - c6af30-dev
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

EOF
}

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

namespaces=(c6af30-dev eb75ad-dev eb75ad-test eb75ad-prod)

for namespace in "${namespaces[@]}"
do
    synch_status=$(compare_patroni_xlog "$namespace")

    echo "The xlogs in namespace $namespace are $synch_status"

    if [ "$synch_status" != "synced" ]; then
        error "the patroni clusters are not synched: ($synch_status)"
        exit 1
    fi
done
