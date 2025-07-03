#!/bin/bash

this="${BASH_SOURCE[0]}"
pwd=$(dirname "$this")
values="$pwd/../values"

KEYCLOAK_HELM_CHART_VERSION="v1.16.7"
KEYCLOAK_HELM_DEPLOYMENT_NAME="sso-keycloak"

upgrade_helm() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  namespace="$1"
  cluster_mode="$2" # active | standby
  current=$(get_current_cluster)

  {
    helm repo add sso-charts https://bcgov.github.io/sso-helm-charts
    helm repo update
  } &>/dev/null

  helm upgrade --install "$KEYCLOAK_HELM_DEPLOYMENT_NAME" \
  sso-charts/sso-keycloak -n "$namespace" \
  --version "$KEYCLOAK_HELM_CHART_VERSION" \
  -f "$values/values.yaml" \
  -f "$values/${namespace:0:6}/${namespace:7}/values-$current-$namespace-$cluster_mode.yaml" "${@:3}"
}

upgrade_helm_active() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  maintenance="false"
  while [[ "$2" =~ ^- && ! "$2" == "--" ]]; do
    case $2 in
    -m | --maintenance-on)
      maintenance="true"
      ;;
    esac
    shift
  done
  current_cluster=$(get_current_cluster)

  # The golddr maintenance page should remain enabled at all times
  if [[ "$current_cluster" == "golddr" ]]; then
    maintenance_enabled="true"
  else
    maintenance_enabled="$maintenance"
  fi

  upgrade_helm "$namespace" "active" \
    --set maintenancePage.enabled="$maintenance_enabled" \
    --set maintenancePage.active="$maintenance"

  connect_route_to_correct_service "$maintenance" "$namespace"
}

upgrade_helm_standby() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  maintenance="false"
  while [[ "$2" =~ ^- && ! "$2" == "--" ]]; do
    case $2 in
    -m | --maintenance-on)
      maintenance="true"
      ;;
    esac
    shift
  done

  current=$(get_current_cluster)
  target=$(get_target_cluster)

  switch_kube_context "$target" "$namespace"
  check_ocp_cluster "$target"

  password_superuser=$(kubectl get secret sso-patroni -n "$namespace" -o jsonpath='{.data.password-superuser}' | base64 -d)
  password_admin=$(kubectl get secret sso-patroni -n "$namespace" -o jsonpath='{.data.password-admin}' | base64 -d)
  password_standby=$(kubectl get secret sso-patroni -n "$namespace" -o jsonpath='{.data.password-standby}' | base64 -d)

  username_appuser1=$(kubectl get secret sso-patroni-appusers -n "$namespace" -o jsonpath='{.data.username-appuser1}' | base64 -d)
  password_appuser1=$(kubectl get secret sso-patroni-appusers -n "$namespace" -o jsonpath='{.data.password-appuser1}' | base64 -d)

  # Get the otp credentials from Gold
  api_token_url=$(kubectl get secret sso-keycloak-otp-credentials -n "$namespace" -o jsonpath='{.data.PPID_API_TOKEN_URL}' | base64 -d)
  api_url=$(kubectl get secret sso-keycloak-otp-credentials -n "$namespace" -o jsonpath='{.data.PPID_API_URL}' | base64 -d)
  client_id=$(kubectl get secret sso-keycloak-otp-credentials -n "$namespace" -o jsonpath='{.data.PPID_CLIENT_ID}' | base64 -d)
  client_secret=$(kubectl get secret sso-keycloak-otp-credentials -n "$namespace" -o jsonpath='{.data.PPID_CLIENT_SECRET}' | base64 -d)
  otp_issuer=$(kubectl get secret sso-keycloak-otp-credentials -n "$namespace" -o jsonpath='{.data.PPID_OTP_ISSUER}' | base64 -d)


  switch_kube_context "$current" "$namespace"
  check_ocp_cluster "$current"

  target_host=$(get_tsc_target_host "$namespace" "sso-patroni")
  target_port=$(get_tsc_target_port "$namespace" "sso-patroni")


  # The postgres.host and postgres port arguments allows the standby keycloak-DR
  # deployment to connect to the patroni-Gold instance via the tsc.
  #   --set postgres.host="$target_host" \
  #   --set postgres.port="$target_port" \

  upgrade_helm "$namespace" "standby" \
    --set patroni.standby.enabled=true \
    --set patroni.standby.host="$target_host" \
    --set patroni.standby.port="$target_port" \
    --set patroni.credentials.superuser.password="$password_superuser" \
    --set patroni.credentials.admin.password="$password_admin" \
    --set patroni.credentials.standby.password="$password_standby" \
    --set patroni.additionalCredentials[0].username="$username_appuser1" \
    --set patroni.additionalCredentials[0].password="$password_appuser1" \
    --set maintenancePage.enabled="$maintenance" \
    --set maintenancePage.active="$maintenance" \
    --set otpCredentials.apiTokenUrl="$api_token_url" \
    --set otpCredentials.apiUrl="$api_url" \
    --set otpCredentials.clientID="$client_id" \
    --set otpCredentials.clientSecret="$client_secret" \
    --set otpCredentials.otpIssuer="$otp_issuer" \
    --set otpCredentials.recreateCredentials=true

  connect_route_to_correct_service "$maintenance" "$namespace"
}

uninstall_helm() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  helm uninstall sso-keycloak -n "$namespace" || true
}

cleanup_namespace() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  kubectl delete configmap -n "$namespace" -l "app.kubernetes.io/name=sso-patroni"
  kubectl delete pvc -n "$namespace" -l "app.kubernetes.io/name=sso-patroni"
}

check_helm_release() {
  if [ "$#" -lt 2 ]; then exit 1; fi
  namespace="$1"
  release="$2"

  status=$(helm status "$release" -n "$namespace" 2>&1)
  error_msg="Error: release: not found"

  if [[ "$status" == *"$error_msg"* ]]; then
    echo "not found"
  else
    echo "found"
  fi
}

get_vanity_route_name() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  if [ "$namespace" = "e4ca1d-dev" ]
  then
    KEYCLOAK_ROUTE="sso-dev-sandbox"
  elif [ "$namespace" = "e4ca1d-test" ]
  then
    KEYCLOAK_ROUTE="sso-test-sandbox"
  elif [ "$namespace" = "e4ca1d-prod" ]
  then
    KEYCLOAK_ROUTE="sso-prod-sandbox"
  elif [ "$namespace" = "eb75ad-dev" ]
  then
    KEYCLOAK_ROUTE="sso-dev"
  elif [ "$namespace" = "eb75ad-test" ]
  then
    KEYCLOAK_ROUTE="sso-test"
  elif [ "$namespace" = "eb75ad-prod" ]
  then
    KEYCLOAK_ROUTE="sso-prod"
  fi

  echo $KEYCLOAK_ROUTE

}

get_vanity_url() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  if [ "$namespace" = "e4ca1d-dev" ]
  then
    KEYCLOAK_URL="dev.sandbox.loginproxy.gov.bc.ca"
  elif [ "$namespace" = "e4ca1d-test" ]
  then
    KEYCLOAK_URL="test.sandbox.loginproxy.gov.bc.ca"
  elif [ "$namespace" = "e4ca1d-prod" ]
  then
    KEYCLOAK_URL="sandbox.loginproxy.gov.bc.ca"
  elif [ "$namespace" = "eb75ad-dev" ]
  then
    KEYCLOAK_URL="dev.loginproxy.gov.bc.ca"
  elif [ "$namespace" = "eb75ad-test" ]
  then
    KEYCLOAK_URL="test.loginproxy.gov.bc.ca"
  elif [ "$namespace" = "eb75ad-prod" ]
  then
    KEYCLOAK_URL="loginproxy.gov.bc.ca"
  fi

  echo $KEYCLOAK_URL

}

connect_route_to_correct_service() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  maintenance="$1"
  namespace="$2"

  KEYCLOAK_ROUTE=$(get_vanity_route_name "$namespace")

  if [ "$maintenance" = "true" ]
  then
    kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p \
    '{"spec":{"to":{"name":"'"$KEYCLOAK_HELM_DEPLOYMENT_NAME"'-maintenance"}}}'
  else
    kubectl -n "$namespace" patch route "$KEYCLOAK_ROUTE" -p \
    '{"spec":{"to":{"name":"'"$KEYCLOAK_HELM_DEPLOYMENT_NAME"'"}}}'
  fi

}
