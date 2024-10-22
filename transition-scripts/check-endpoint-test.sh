#!/bin/bash
set -e

usage() {
    cat <<EOF
This will only pass if the health check for the namespace and cluster pass.
It also requires the response be in json format which only works for keycloak,
not the maintenance page.

Usages:
    $0 <namespace> <cluster>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

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
source "$pwd/helpers/_all.sh"

# loop on the health endpoint every 20 seconds untill it passes while pointed at keycloak
wait_for_keycloak_up() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  cluster="$2"


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

  count=0

  wait_for_keycloak() {
    response=$(curl -I --resolve "$KEYCLOAK_URL":443:"$IP" -H \'Host:"$KEYCLOAK_URL"\' \
    https://"$KEYCLOAK_URL"/auth/realms/master/.well-known/openid-configuration)

    status_code="$(echo "$response" | grep 'HTTP/1.1' | awk '{print $2}')"

    if [ "$status_code" = "200" ]; then
        json_response=$(curl --resolve "$KEYCLOAK_URL":443:"$IP" -H \'Host:"$KEYCLOAK_URL"\' \
        https://"$KEYCLOAK_URL"/auth/realms/master/.well-known/openid-configuration)

        if echo "$json_response" | jq empty 2>/dev/null; then
            # echo "THE ISSUER IS:"
            # issuer=$(echo "$json_response" | jq -r '.issuer')
            # echo "$issuer"
            echo "Keycloak is up"
            # return 1
        else
            echo "Maintenance page is up."
        fi
    else
        echo "Endpoint down."
    fi

    if [[ "$count" -gt 500 ]]; then
      warn "keycloak in ""$namespace"" ""$cluster"" did not reach a healthy state"
      exit 1
    fi

    count=$((count + 1))

  }

  while wait_for_keycloak; do sleep 3; done
}

wait_for_keycloak_up "$namespace" "$cluster"
