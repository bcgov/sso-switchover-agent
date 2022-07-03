#!/bin/bash

GITHUB_ORG="bcgov"
GITHUB_REPO="sso-switchover-agent"

trigger_github_dispatcher() {
  if [ "$#" -lt 4 ]; then exit 1; fi
  gh_token="$1"
  workflow="$2"
  namespace="$3"
  sleep="$4"

  read -r status_code data < <(curl_http_code -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $gh_token" \
    -d '{"ref": "main", "inputs": { "namespace":'\""$namespace\""'}}' \
    https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/actions/workflows/$workflow/dispatches)
  
  if [ "$status_code" -ne "204" ]; then
    warn "failed to trigger github action $workflow"
    warn "$data"
    exit 1;
  fi

  sleep $sleep
  info "successfully triggered github action $workflow"
}
