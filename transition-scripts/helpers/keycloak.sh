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
