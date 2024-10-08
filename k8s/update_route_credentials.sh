#!/bin/bash
set -e

usage() {
    cat <<EOF
Deploy Keycloak resources in the target namespaces in a normal situation;
it sets "active" mode in Gold cluster and "standby" mode in Golddr cluster.

Usages:
    $0 <namespace>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Examples:
    $ $0 e4ca1d-dev
EOF
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

namespace=$1
year=$2

# pwd="$(dirname "$0")"
# source "$pwd/helpers/_all.sh"

KEYCLOAK_ROUTE="sso-dev-sandbox"

keyEncoded=$(kubectl -n "$namespace" get secret loginproxy-ssl-cert-secret."$year" -o jsonpath='{.data.private-key}' )
key=$(echo -e "$keyEncoded" | base64 --decode | sed ':a;N;$!ba;s/\n/\\n/g')

certificateEncoded=$(kubectl -n "$namespace" get secret loginproxy-ssl-cert-secret."$year" -o jsonpath='{.data.certificate}')
certificate=$(echo -e "$certificateEncoded" | base64 --decode | sed ':a;N;$!ba;s/\n/\\n/g')

caCertificateEncoded=$(kubectl -n "$namespace" get secret loginproxy-ssl-cert-secret."$year" -o jsonpath='{.data.ca-chain-certificate}')
caCertificate=$(echo -e "$caCertificateEncoded" | base64 --decode | sed ':a;N;$!ba;s/\n/\\n/g')

kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p '{"spec":{"tls":{"certificate":"'"$certificate"'", "key":"'"$key"'", "caCertificate":"'"$caCertificate"'" }}}'
