#!/bin/bash

#######################
## Generic Functions ##
#######################

OC_SERVICE_ACCOUNT="sso-action-deployer"

KUBE_RETRY_ATTEMPTS="${KUBE_RETRY_ATTEMPTS:-5}"
KUBE_RETRY_DELAY="${KUBE_RETRY_DELAY:-5}"
KUBE_CONNECTION_ERROR_REGEX="connection refused|connection reset|i/o timeout|TLS handshake timeout|unexpected EOF|unable to connect to the server|no route to host|network is unreachable|Client.Timeout|context deadline exceeded|Service Unavailable|Gateway Time-?out|Bad Gateway"

# Runs a command, retrying (fixed delay) only when its stderr shows a connection-type error.
# kubectl can log an API discovery timeout and still exit 0 with empty/partial output, so a
# connection error in stderr triggers a retry even when the exit code is 0.
# Output of each attempt is buffered; only the final attempt's stdout/stderr is emitted.
retry_on_connection_error() {
  local attempt=1 rc outfile errfile
  outfile=$(mktemp)
  errfile=$(mktemp)

  while true; do
    "$@" >"$outfile" 2>"$errfile"
    rc=$?

    if [[ "$attempt" -lt "$KUBE_RETRY_ATTEMPTS" ]] && grep -qiE "$KUBE_CONNECTION_ERROR_REGEX" "$errfile"; then
      echo "$1 connection error (attempt $attempt/$KUBE_RETRY_ATTEMPTS), retrying in ${KUBE_RETRY_DELAY}s..." >&2
      attempt=$((attempt + 1))
      sleep "$KUBE_RETRY_DELAY"
      continue
    fi

    cat "$outfile"
    cat "$errfile" >&2
    rm -f "$outfile" "$errfile"
    return "$rc"
  done
}

kubectl_with_retry() {
  retry_on_connection_error kubectl "$@"
}

helm_with_retry() {
  retry_on_connection_error helm "$@"
}

oc_with_retry() {
  retry_on_connection_error oc "$@"
}

get_kube_context() {
  kubectl config current-context
}

check_kube_context() {
  if [[ "$#" -lt 1 ]]; then exit 1; fi
  partial="$1"
  context=$(get_kube_context)

  if [[ "$context" != *"$partial"* ]]; then
    echo "working on an invalid kubenetes context ($context)"
    exit 1
  fi
}

check_ocp_cluster() {
  cluster="$1"
  check_kube_context "api-$cluster-devops-gov-bc-ca"
}

get_current_cluster() {
  # When running inside a cluster (e.g. the switchover agent pod) there are no named contexts
  if [[ -n "$IN_CLUSTER_NAME" ]]; then
    echo "$IN_CLUSTER_NAME"
    return
  fi

  gold="api-gold-devops-gov-bc-ca"
  golddr="api-golddr-devops-gov-bc-ca"

  context=$(get_kube_context)
  if [[ "$context" == *"$gold"* ]]; then
    echo "gold"
  elif [[ "$context" == *"$golddr"* ]]; then
    echo "golddr"
  else
    echo "none"
  fi
}

get_ocp_plate() {
  if [[ "$#" -lt 1 ]]; then exit 1; fi
  namespace="$1"
  echo "$namespace" | cut -d "-" -f 1
}

count_kube_contexts() {
  count=$(kubectl config get-contexts --no-headers | wc -l)
  echo "$count"
}

switch_kube_context() {
  if [[ "$#" -lt 1 ]]; then exit 1; fi
  cluster="$1"

  if [[ "$(count_kube_contexts)" -lt 2 ]]; then
    echo "expects two contexts at least; one in gold and one in golddr"
    exit 1
  fi

  context_name=$(kubectl config get-contexts --no-headers -o name | grep "api-$cluster-devops-gov-bc-ca:6443/system:serviceaccount:.*:$OC_SERVICE_ACCOUNT" | head -n 1)
  if [[ -z "$context_name" ]]; then
    echo "kubenetes context not found"
    exit 1
  fi

  kubectl config use-context "$context_name"
  check_ocp_cluster "$cluster"
}

ensure_kube_context() {
  if [[ "$#" -lt 1 ]]; then exit 1; fi
  cluster="$1"

  current=$(get_current_cluster)

  if [[ "$(get_current_cluster)" != "$cluster" ]]; then
    switch_kube_context "$cluster"
  fi
}

curl_http_code() {
  response=$(curl -s -w "%{http_code}" "${@:1}")
  if [[ "${#response}" -lt 3 ]]; then
    echo "500" ""
    return
  fi

  status_code=${response: -3}
  data=${response:0:-3}

  echo "$status_code" "$data"
}

kube_curl() {
  if [[ "$#" -lt 2 ]]; then exit 1; fi

  namespace="$1"
  pod_name="$2"

  response=$(kubectl_with_retry -n "$namespace" exec "$pod_name" -- curl -s -w "%{http_code}" "${@:3}")
  if [[ "${#response}" -lt 3 ]]; then
    echo "500" ""
    return
  fi

  status_code=${response: -3}
  data=${response:0:-3}

  echo "$status_code" "$data"
}

get_target_cluster() {
  current=$(get_current_cluster)
  target=$([[ "$current" == "gold" ]] && echo "golddr" || echo "gold")
  echo "$target"
}

get_tsc_target_host() {
  if [[ "$#" -lt 2 ]]; then exit 1; fi

  namespace="$1"
  prefix="$2"

  target=$(get_target_cluster)
  target_host="$prefix-$target.$namespace.svc.cluster.local"
  echo "$target_host"
}

get_tsc_target_port() {
  if [[ "$#" -lt 2 ]]; then exit 1; fi

  namespace="$1"
  prefix="$2"

  target=$(get_target_cluster)
  target_port=$(kubectl_with_retry get svc "$prefix-$target" -n "$namespace" -o jsonpath='{.spec.ports[].targetPort}')
  echo "$target_port"
}

count_ready_pods() {
  if [[ "$#" -lt 1 ]]; then exit 1; fi
  namespace="$1"

  kubectl_with_retry -n "$namespace" get pods -o custom-columns=ready:status.containerStatuses[*].ready "${@:2}" | grep true -c
}

get_ocp_default_route_url() {
  if [[ "$#" -lt 3 ]]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  routename="$3"

  url="https://$routename-$namespace.apps.$cluster.devops.gov.bc.ca"

  echo "$url"
}
