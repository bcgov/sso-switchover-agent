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


ipresolved=$(gethostip -d "$url_to_resolve")

if [ "$cluster" == gold ] && [ "$ipresolved" == "142.34.229.4" ]; then
    echo "The GSLB is point traffic to gold"
elif [ "$cluster" == golddr ] && [ "$ipresolved" == "142.34.64.4" ]; then
    echo "The GSLB is point traffic to golddr"
else
    error "The GSLB is not directing traffic to the correct cluster"
    exit 1
fi
