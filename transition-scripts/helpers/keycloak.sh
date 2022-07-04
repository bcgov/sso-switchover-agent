#!/bin/bash

count_ready_keycloak_pods() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  count_ready_pods "$namespace" -l app.kubernetes.io/name=sso-keycloak
}

wait_for_keycloak_all_ready() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  replicas=$(kubectl get deployment sso-keycloak -n "$namespace" -o jsonpath='{.spec.replicas}')

  count=0
  wait_ready() {
    ready_count=$(count_ready_keycloak_pods "$namespace")
    info "keycloak ready $ready_count/$replicas"

    if [ "$ready_count" == "$replicas" ]; then return 1; fi

    # wait for 30mins
    if [[ "$count" -gt 360 ]]; then
      warn "keycloak replicas is not ready"
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_ready; do sleep 5; done
}

get_ocp_keycloak_url() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"

  url=$(get_ocp_default_route_url "$cluster" "$namespace" "sso-keycloak")

  echo "$url"
}

check_keycloak_health() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"

  read -r status_code data < <(curl_http_code \
    "$(get_ocp_keycloak_url "$cluster" "$namespace")/auth/realms/master/.well-known/openid-configuration")

  if [ "$status_code" -ne "200" ] || [ "$data" == null ]; then
    echo "down"
    return
  fi

  echo "up"
}

wait_for_keycloak_healthy() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"

  count=0
  wait_keycloak_up() {
    status=$(check_keycloak_health "$cluster" "$namespace")
    info "checking keycloak app health - $status"

    if [ "$status" == "up" ]; then return 1; fi

    if [[ "$count" -gt 50 ]]; then
      warn "keycloak app is not healthy"
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_keycloak_up; do sleep 5; done
}

get_keycloak_admin_token() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  ensure_kube_context "$cluster"

  username=$(kubectl get secret sso-keycloak-admin -n "$namespace" -o jsonpath='{.data.username}' | base64 -d)
  password=$(kubectl get secret sso-keycloak-admin -n "$namespace" -o jsonpath='{.data.password}' | base64 -d)

  read -r status_code data < <(curl_http_code \
    -d "client_id=admin-cli" \
    -d "username=$username" \
    -d "password=$password" \
    -d "grant_type=password" \
    "$(get_ocp_keycloak_url "$cluster" "$namespace")/auth/realms/master/protocol/openid-connect/token")

  if [ "$status_code" -ne "200" ] || [ "$data" == null ]; then
    warn "failed to fetch Keycloak admin access token"
    exit 1
  fi

  access_token=$(echo "$data" | jq -r '.access_token')

  echo "$access_token"
}

curl_keycloak_api() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  ensure_kube_context "$cluster"

  access_token=$(get_keycloak_admin_token "$cluster" "$namespace")

  read -r status_code data < <(curl_http_code \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" "${@:3}")

  echo "$status_code" "$data"
}

create_keycloak_realm() {
  if [ "$#" -lt 3 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  realmname="$3"
  ensure_kube_context "$cluster"

  read -r status_code data < <(curl_keycloak_api "$cluster" "$namespace" -X POST \
    -d '{"realm":'\""$realmname\""'}' \
    "$(get_ocp_keycloak_url "$cluster" "$namespace")/auth/admin/realms")

  if [ "$status_code" -ne "201" ]; then
    error "$status_code: failed to create a new realm"
    error "$data"
    exit 1
  fi

  echo "success"
}

get_keycloak_realm() {
  if [ "$#" -lt 3 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  realmname="$3"
  ensure_kube_context "$cluster"

  read -r status_code data < <(curl_keycloak_api "$cluster" "$namespace" -X GET \
    "$(get_ocp_keycloak_url "$cluster" "$namespace")/auth/admin/realms/$realmname")

  if [ "$status_code" -ne "200" ]; then
    return
  fi

  echo "$data"
}

list_keycloak_realms() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  ensure_kube_context "$cluster"

  read -r status_code data < <(curl_keycloak_api "$cluster" "$namespace" -X GET \
    "$(get_ocp_keycloak_url "$cluster" "$namespace")/auth/admin/realms")

  if [ "$status_code" -ne "200" ]; then
    return
  fi

  echo "$data"
}

delete_keycloak_realm() {
  if [ "$#" -lt 3 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"
  realmname="$3"
  ensure_kube_context "$cluster"

  read -r status_code data < <(curl_keycloak_api "$cluster" "$namespace" -X DELETE \
    "$(get_ocp_keycloak_url "$cluster" "$namespace")/auth/admin/realms/$realmname")

  if [ "$status_code" -ne "204" ]; then
    return
  fi

  echo "$data"
}

remove_all_realms() {
  if [ "$#" -lt 2 ]; then exit 1; fi

  cluster="$1"
  namespace="$2"

  realms=$(list_keycloak_realms "$cluster" "$namespace")
  for row in $(echo "$realms" | jq -r '.[] | @base64'); do
    getrealm() {
      echo "$row" | base64 --decode | jq -r "$1"
    }

    name=$(getrealm '.realm')
    if [ "$name" != "master" ]; then
      delete_keycloak_realm "$cluster" "$namespace" "$name"
    fi
  done
}
