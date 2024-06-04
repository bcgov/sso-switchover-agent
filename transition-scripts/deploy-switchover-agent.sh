#!/bin/bash
set -e

usage() {
    cat <<EOF
Redeploy the switchover agent in <namespace> with time an optional preemptive failover failback argument.

Usages:
    $0 <namespace> <time_start> <time_end>

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Time format is "YYYY/MM/DD HH:MM". There must be 1 or 3 arguments supplied for the script to run.

Examples:
    $ $0 e4ca1d-dev "1984/12/12 17:30" "2001/12/12 03:30"
EOF
}

if [[ "$#" -ne 1 && "$#" -ne 3 ]]; then
    usage
    exit 1
fi

namespace=$1
secret_name="sso-switchover-agent"
pwd="$(dirname "$0")"
source "$pwd/helpers/_all.sh"


validate_time_regex() {
  local input="$1"
  #TODO IMPROVE THIS REGEX
  local regex="^2[0-9]{3}\/[0-9]{2}\/[0-9]{2}\s[0-9]{2}:[0-9]{2}$"
  if [[ "$input" =~ $regex ]]; then
    echo "The input matches the time regex."
    return 0
  else
    echo "The input does not match the time regex."
    exit 1
  fi
}


# Switchover Agent deployment is in  the Golddr cluster
switch_kube_context "golddr" "$namespace"
check_ocp_cluster "golddr"

if [[ "$#" -eq 3 ]]; then
    time_start=$2
    time_end=$3
    validate_time_regex "$time_start"
    validate_time_regex "$time_end"

    kubectl -n "$namespace" patch secret "$secret_name" \
    --patch='{"stringData": { "PREEMPTIVE_FAILOVER_START_TIME": "'"$time_start"'", "PREEMPTIVE_FAILOVER_END_TIME": "'"$time_end"'" }}'
elif [[ "$#" -eq 1 ]]; then

    kubectl -n "$namespace" patch secret "$secret_name" \
    --patch='{"stringData": { "PREEMPTIVE_FAILOVER_START_TIME": "", "PREEMPTIVE_FAILOVER_END_TIME": "" }}'
fi

# Redeploy the agent.

kubectl -n "$namespace" rollout restart deployment/switch-agent-switchover-agent
