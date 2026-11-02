#!/bin/bash

this="${BASH_SOURCE[0]}"
pwd="$(dirname "$this")"

# Reuse the shared transition-scripts helpers (kube_curl, ensure_kube_context,
# check_patroni_cluster_mode, wait_for_patroni_healthy, wait_for_keycloak_all_ready,
# info/warn/error, etc.) instead of duplicating them here.
# shellcheck disable=SC1091
source "$pwd/../../transition-scripts/helpers/_all.sh"

for f in "$pwd"/*; do
  [ "$this" == "$f" ] && continue # skip itself
  [ -d "$f" ] && continue         # skip directories
  [ -L "${f%/}" ] && continue     # skip symlinks

  echo "loading helper: $f"

  # shellcheck disable=SC1090
  source "$f"
done
