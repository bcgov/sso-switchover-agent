#!/bin/bash
set -e

usage() {
  cat <<EOF
Rotate the Patroni system credentials (admin, standby, superuser) and the
Keycloak app (appuser1) credential for the Gold cluster, with zero downtime.

Steps (rotate mode):
    1. Confirm the patroni cluster in Gold is healthy and active.
    2. Back up the current sso-patroni & sso-patroni-appusers secret data
       into sso-patroni-old-creds.
    3. Rotate the admin/standby/superuser passwords in Postgres and update
       the sso-patroni secret, then rolling-restart the patroni pods
       (replicas first, graceful leadership handoff, old leader last).
    4. Create a new appuser role that inherits the old appuser role's
       privileges (both remain valid), update sso-patroni-appusers, then
       cycle Keycloak (and, once known, backupcontainer) so they pick up
       the new credential. The old appuser role is *not* dropped here.

Finalize mode (run later, once the new appuser credential is confirmed to
be in use everywhere):
    5. Reassign ownership from the old appuser role to the new one, then
       drop the old role.

Usages:
    $0 <namespace> [--dry-run|--no-dry-run] [--finalize]

Available namespaces:
    - e4ca1d-dev
    - e4ca1d-test
    - e4ca1d-prod
    - eb75ad-dev
    - eb75ad-test
    - eb75ad-prod

Pre-conditions:
    - must be logged into the Gold cluster (GoldDR is out of scope for this
      rotation).
    - the patroni cluster in Gold must be healthy and in active mode.

Examples:
    $ $0 e4ca1d-dev --dry-run
    $ $0 e4ca1d-dev --no-dry-run
    $ $0 e4ca1d-dev --no-dry-run --finalize
EOF
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

namespace=$1
shift

dry_run="true"
finalize="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run)
    dry_run="true"
    ;;
  --no-dry-run)
    dry_run="false"
    ;;
  --finalize)
    finalize="true"
    ;;
  *)
    echo "Unknown argument: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

pwd="$(dirname "$0")"
# shellcheck disable=SC1091
source "$pwd/helpers/_all.sh"

info "Ensure cluster is gold."
ensure_kube_context "gold"

if [ "$finalize" = "true" ]; then
  info "Finalizing appuser rotation in $namespace (dry_run=$dry_run)"
  finalize_appuser_rotation "$namespace" "$dry_run"
  info "Finalize complete for $namespace"
  exit 0
fi

info "Starting credential rotation for $namespace (dry_run=$dry_run)"

patroni_mode=$(check_patroni_cluster_mode "$namespace")
if [ "$patroni_mode" != "active" ]; then
  error "the patroni cluster in $namespace is not in active mode ($patroni_mode); aborting"
  exit 1
fi

wait_for_patroni_healthy "$namespace"
wait_for_patroni_all_ready "$namespace"

backup_patroni_secrets "$namespace" "$dry_run"

rotate_system_role_passwords "$namespace" "$dry_run"
cycle_patroni_pods_zero_downtime "$namespace" "$dry_run"

rotate_appuser_role "$namespace" "$dry_run"
cycle_keycloak_pods "$namespace" "$dry_run"
cycle_backupcontainer_pod "$namespace" "$dry_run"

# See credential-rotation/helpers/rotate.sh for the commented-out Grafana
# reminder block.

info "Credential rotation complete for $namespace (dry_run=$dry_run)."
info "Run this script again with --finalize once the new appuser credential is confirmed working everywhere, to drop the old appuser role."
