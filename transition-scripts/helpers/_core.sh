#!/bin/bash

#######################
## Generic Functions ##
#######################

OC_SERVICE_ACCOUNT="oc-sso-deployer"

get_kube_context() {
  kubectl config current-context
}

check_kube_context() {
  if [ "$#" -lt 1 ]; then exit 1; fi
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
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  echo "$namespace" | cut -d "-" -f 1
}

count_kube_contexts() {
  count=$(kubectl config get-contexts --no-headers | wc -l)
  echo "$count"
}

switch_kube_context() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  cluster="$1"

  if [ "$(count_kube_contexts)" -lt 2 ]; then
    echo "expects two contexts at least; one in gold and one in golddr"
    exit 1
  fi

  context_name=$(kubectl config get-contexts --no-headers -o name | grep "api-$cluster-devops-gov-bc-ca:6443/system:serviceaccount:.*:$OC_SERVICE_ACCOUNT" | head -n 1)
  if [ -z "$context_name" ]; then
    echo "kubenetes context not found"
    exit 1
  fi

  kubectl config use-context "$context_name"
  check_ocp_cluster "$cluster"
}

ensure_kube_context() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  cluster="$1"

  current=$(get_current_cluster)

  if [ "$(get_current_cluster)" != "$cluster" ]; then
    switch_kube_context "$cluster"
  fi
}

curl_http_code() {
  response=$(curl -s -w "%{http_code}" "${@:1}")
  if [ "${#response}" -lt 3 ]; then
    echo "500" ""
    return
  fi

  status_code=${response: -3}
  data=${response:0:-3}

  echo "$status_code" "$data"
}

kube_curl() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  pod_name="$2"

  response=$(kubectl -n "$namespace" exec "$pod_name" -- curl -s -w "%{http_code}" "${@:3}")
  if [ "${#response}" -lt 3 ]; then
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
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  prefix="$2"

  target=$(get_target_cluster)
  target_host="$prefix-$target.$namespace.svc.cluster.local"
  echo "$target_host"
}

get_tsc_target_port() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  prefix="$2"

  target=$(get_target_cluster)
  target_port=$(kubectl get svc "$prefix-$target" -n "$namespace" -o jsonpath='{.spec.ports[].targetPort}')
  echo "$target_port"
}

count_ready_pods() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  kubectl -n "$namespace" get pods -o custom-columns=ready:status.containerStatuses[*].ready "${@:2}" | grep true -c
}

get_ocp_default_route_url() {
  if [ "$#" -lt 3 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  routename="$3"

  url="https://$routename-$namespace.apps.$cluster.devops.gov.bc.ca"

  echo "$url"
}
