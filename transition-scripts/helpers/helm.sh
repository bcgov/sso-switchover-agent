#!/bin/bash

this="${BASH_SOURCE[0]}"
pwd=$(dirname "$this")
values="$pwd/../values"

KEYCLOAK_HELM_CHART_VERSION="v1.7.1"
KEYCLOAK_HELM_DEPLOYMENT_NAME="sso-keycloak"

upgrade_helm() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  cluster_mode="$2" # active | standby
  current=$(get_current_cluster)

  helm repo add sso-charts https://bcgov.github.io/sso-helm-charts
  helm repo update

  helm upgrade --install "$KEYCLOAK_HELM_DEPLOYMENT_NAME" sso-charts/sso-keycloak -n "$namespace" --version "$KEYCLOAK_HELM_CHART_VERSION" -f "$values/values.yaml" -f "$values/values-$current-$namespace-$cluster_mode.yaml" "${@:3}"
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
