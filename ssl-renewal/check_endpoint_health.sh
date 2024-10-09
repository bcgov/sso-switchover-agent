#!/bin/bash
set -e

usage() {
    cat <<EOF
This checks the status of the keycloak app for a given namespace and cluster.
It is the same check the GSLB uses to establish the applications health.
It also provides the expiration date for the SSL cert on the route.

Usages:
    $0 <namespace> <cluster>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod
Available Clusters
    - gold
    - golddr



Examples:
    $ $0 e4ca1d-dev gold
EOF
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

namespace=$1
cluster=$2

pwd="$(dirname "$0")"
source "$pwd/../transition-scripts/helpers/_all.sh"

check_ocp_cluster "$cluster"


KEYCLOAK_URL=$(get_vanity_url "$namespace")

# Get the cluster ip address.
if [ "$cluster" = "golddr" ]; then
    IP="142.34.64.4"
elif [ "$cluster" = "gold" ]; then
    IP="142.34.229.4"
else
    echo "Cluster must be gold or golddr"
    exit 1
fi

curl -Iv --resolve "$KEYCLOAK_URL":443:"$IP" -H '"Host:'"$KEYCLOAK_URL"'"' \
https://"$KEYCLOAK_URL"/auth/realms/master/.well-known/openid-configuration


curl -Iv --resolve "$KEYCLOAK_URL":443:"$IP" -H '"Host:'"$KEYCLOAK_URL"'"' \
https://"$KEYCLOAK_URL"/auth/realms/master/.well-known/openid-configuration  \
--stderr - | grep "expire date"
