#!/bin/bash

pwd="$(dirname "$0")"
values="$pwd/values"

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

count_kube_contexts() {
  count=$(kubectl config get-contexts --no-headers | wc -l)
  echo "$count"
}

switch_kube_context() {
  if [ "$#" -lt 2 ]; then exit 1; fi
  cluster="$1"
  namespace="$2"

  if [ "$(count_kube_contexts)" -lt 2 ]; then
    echo "expects two contexts at least; one in gold and one in golddr"
    exit 1
  fi

  context_name=$(kubectl config get-contexts --no-headers -o name | grep "api-$cluster-devops-gov-bc-ca:6443/system:serviceaccount:$namespace" | head -n 1)
  if [ -z "$context_name" ]; then
    echo "kubenetes context not found"
    exit 1
  fi

  kubectl config use-context "$context_name"
}

kube_curl() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  pod_name="$2"

  response=$(kubectl -n "$namespace" exec "$pod_name" -- curl -s -w "%{http_code}" "${@:3}")
  status_code=${response: -3}
  data=${response:0:-3}

  echo "$status_code" "$data"
}

# see https://patroni.readthedocs.io/en/latest/rest_api.html#patroni-rest-api
# `GET /health`: returns HTTP status code 200 only when PostgreSQL is up and running.
check_patroni_health() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 http://localhost:8008/health)

  patroni_status=$(echo "$data" | jq -r '.state')
  if [ "$status_code" -ne "200" ] || [ "$patroni_status" != "running" ]; then
    echo "down"
    return
  fi

  echo "up"
}

wait_for_patroni_healthy() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  count=0
  wait_patroni_up() {
    patroni_health=$(check_patroni_health "$namespace")
    echo "patroni health - $patroni_health"

    if [ "$patroni_health" == "up" ]; then return 1; fi

    if [[ "$count" -gt 50 ]]; then
      echo "The current context ($(get_kube_context)) patroni pod is not running"
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_patroni_up; do sleep 5; done
}

check_patroni_cluster_mode() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 http://localhost:8008/config)
  if [ "$status_code" -ne "200" ]; then
    echo "inactive"
    return
  fi

  standby_cluster_config=$(echo "$data" | jq -r '.standby_cluster')
  if [ "$standby_cluster_config" == null ]; then
    echo "active"
  else
    echo "standby"
  fi
}

set_patroni_cluster_active() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 -XPATCH -d '{"standby_cluster":null}' http://localhost:8008/config)
  if [ "$status_code" -ne "200" ]; then
    echo "failure"
    return
  fi

  standby_cluster_config=$(echo "$data" | jq -r '.standby_cluster')
  if [ "$standby_cluster_config" != null ]; then
    echo "failure"
    return
  fi

  echo "success"
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

set_patroni_cluster_standby() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  target_host=$(get_tsc_target_host "$namespace" "sso-patroni")
  target_port=$(get_tsc_target_port "$namespace" "sso-patroni")
  if [ -z "$target_port" ]; then exit 1; fi

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 -XPATCH -d '{"standby_cluster":{"create_replica_methods":["basebackup_fast_xlog"],"host":'\""$target_host\""',"port":'"$target_port"'}}' http://localhost:8008/config)
  if [ "$status_code" -ne "200" ]; then
    echo "failure"
    return
  fi

  standby_cluster_config=$(echo "$data" | jq -r '.standby_cluster')
  if [ "$standby_cluster_config" == null ]; then
    echo "failure"
    return
  fi

  echo "success"
}

upgrade_helm() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  cluster_mode="$2" # active | standby
  current=$(get_current_cluster)

  helm repo add sso-charts https://bcgov.github.io/sso-helm-charts
  helm repo update

  helm upgrade --install sso-keycloak sso-charts/sso-keycloak -n "$namespace" --version v1.7.1 -f "$values/values.yaml" -f "$values/values-$current-$namespace-$cluster_mode.yaml" "${@:3}"
}

upgrade_helm_active() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  upgrade_helm "$namespace" "active"
}

upgrade_helm_standby() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  current=$(get_current_cluster)
  target=$(get_target_cluster)

  switch_kube_context "$target" "$namespace"
  check_ocp_cluster "$target"

  password_superuser=$(kubectl get secret sso-patroni -n "$namespace" -o jsonpath='{.data.password-superuser}' | base64 -d)
  password_admin=$(kubectl get secret sso-patroni -n "$namespace" -o jsonpath='{.data.password-admin}' | base64 -d)
  password_standby=$(kubectl get secret sso-patroni -n "$namespace" -o jsonpath='{.data.password-standby}' | base64 -d)

  username_appuser1=$(kubectl get secret sso-patroni-appusers -n "$namespace" -o jsonpath='{.data.username-appuser1}' | base64 -d)
  password_appuser1=$(kubectl get secret sso-patroni-appusers -n "$namespace" -o jsonpath='{.data.password-appuser1}' | base64 -d)

  switch_kube_context "$current" "$namespace"
  check_ocp_cluster "$current"

  target_host=$(get_tsc_target_host "$namespace" "sso-patroni")
  target_port=$(get_tsc_target_port "$namespace" "sso-patroni")

  upgrade_helm "$namespace" "standby" \
    --set postgres.host="$target_host" \
    --set postgres.port="$target_port" \
    --set patroni.standby.enabled=true \
    --set patroni.standby.host="$target_host" \
    --set patroni.standby.port="$target_port" \
    --set patroni.credentials.superuser.password="$password_superuser" \
    --set patroni.credentials.admin.password="$password_admin" \
    --set patroni.credentials.standby.password="$password_standby" \
    --set patroni.additionalCredentials[0].username="$username_appuser1" \
    --set patroni.additionalCredentials[0].password="$password_appuser1"
}

uninstall_helm() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  helm uninstall sso-keycloak || true
}

cleanup_namespace() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  kubectl delete configmap -n "$namespace" -l "app.kubernetes.io/name=sso-patroni"
  kubectl delete pvc -n "$namespace" -l "app.kubernetes.io/name=sso-patroni"
}
