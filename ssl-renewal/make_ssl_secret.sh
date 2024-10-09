#!/bin/bash
set -e

usage() {
    cat <<EOF
Creates a secret in the namespace provided for the year provided.

Usages:
    $0 <namespace> <year>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Examples:
    $ $0 e4ca1d-dev 2014
EOF
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

namespace=$1
year=$2

pwd="$(dirname "$0")"

oc -n "$namespace" create secret generic loginproxy-ssl-cert-secret."$year" \
 --from-file=private-key="$pwd"/.env/"$namespace"/loginproxy.key \
 --from-file=certificate="$pwd"/.env/"$namespace"/loginproxy.txt \
 --from-file=csr="$pwd"/.env/"$namespace"/loginproxy.csr \
 --from-file=ca-chain-certificate="$pwd"/.env/"$namespace"/L1K-for-certs.txt \
 --from-file=ca-root-certifcate="$pwd"/.env/"$namespace"/L1K-root-for-certs-G2.txt
