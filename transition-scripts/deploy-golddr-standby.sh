#!/bin/bash

NAMESPACE=$1

pwd="$(dirname "$0")"
values="$pwd/values"
source "$pwd/helpers.sh"

if ! check_kube_context "api-golddr-devops-gov-bc-ca"; then
    echo "invalid context"
    exit 1
fi

helm repo add sso-charts https://bcgov.github.io/sso-helm-charts
helm repo update

helm upgrade --install sso-keycloak sso-charts/sso-keycloak \
 -n "$NAMESPACE" -f "$values/values.yaml" -f "$values/values-golddr-$NAMESPACE.yaml"  \
 --version v1.7.1
