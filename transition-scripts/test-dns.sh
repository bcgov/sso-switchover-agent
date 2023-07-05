#!/bin/bash
set -e

usage() {
    cat <<EOF
Test that a url points at a specific DNS

Usages:
    $0 url cluster

Available clusters:
    - gold
    - golddr

Examples:
    $ $0 dev.sandbox.loginproxy.gov.bc.ca gold
EOF
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"

url_to_resolve=$1
cluster=$2


# ipresolved=$(gethostip -d "$url_to_resolve")

# if [ "$cluster" == gold ] && [ "$ipresolved" == "142.34.229.4" ]; then
#     echo "The GSLB is point traffic to gold"
# elif [ "$cluster" == golddr ] && [ "$ipresolved" == "142.34.64.4" ]; then
#     echo "The GSLB is point traffic to golddr"
# else
#     error "The GSLB is not directing traffic to the correct cluster"
#     exit 1
# fi



# wait_for_GSLB_to_point_at_cluster() {
#   if [ "$#" -lt 1 ]; then exit 1; fi

#   namespace="$1"

#   replicas=$(kubectl get deployment sso-keycloak -n "$namespace" -o jsonpath='{.spec.replicas}')

count=0
wait_ready() {
    ipresolved=$(gethostip -d "$url_to_resolve")
# ready_count=$(count_ready_keycloak_pods "$namespace")
    info "The GSLB is resolving the IP: $ipresolved"

    if [ "$cluster" == gold ] && [ "$ipresolved" == "142.34.229.4" ]; then
        echo "The GSLB is point traffic to gold"
        return 1
    elif [ "$cluster" == golddr ] && [ "$ipresolved" == "142.34.64.4" ]; then
        echo "The GSLB is point traffic to golddr"
        return 1
    else
        error "The GSLB is not directing traffic to the correct cluster"
    fi


# if [ "$ready_count" == "$replicas" ]; then return 1; fi

# wait for 10mins
if [[ "$count" -gt 120 ]]; then
    warn "The GSLB did not point to the $cluster cluster in 10 min."
    exit 1
fi

count=$((count + 1))
}

while wait_ready; do sleep 5; done
