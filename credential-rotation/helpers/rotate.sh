#!/bin/bash

# Credential rotation helpers for the Gold Patroni cluster backing Keycloak.
#
# ASSUMPTIONS THAT NEED CONFIRMING AGAINST THE ACTUAL sso-patroni HELM CHART:
#   - The Postgres *role names* match the secret key suffixes used below
#     (superuser -> postgres, admin -> admin, standby -> standby). Override
#     these with env vars if the real chart uses different role names.
#   - The chart does NOT declaratively drop/replace DB roles that disappear
#     from `patroni.additionalCredentials` on `helm upgrade`. This script
#     therefore manages the appuser role directly via SQL + a plain secret
#     patch and deliberately avoids re-running `helm upgrade` for the appuser
#     rotation step until that assumption is verified (see
#     credential-rotation/README.md).
SUPERUSER_ROLE="postgres"
ADMIN_ROLE="admin"
STANDBY_ROLE="standby"

PATRONI_SECRET="sso-patroni"
APPUSER_SECRET="sso-patroni-appusers"
BACKUP_SECRET="sso-patroni-old-creds"

#######################################
## Generic secret / password helpers ##
#######################################

# Generate a random password that is safe to embed in a psql connection
# string, JDBC URL, and shell heredoc (alphanumeric only).
generate_password() {
  length="${1:-32}"
  # openssl rand emits base64; strip everything except alphanumerics and trim.
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$length"
}

# A short, sortable suffix used to make new appuser role names unique
# (e.g. appuser1-20260101120000).
generate_rotation_suffix() {
  date -u +%Y%m%d%H%M%S
}

get_secret_value() {
  if [ "$#" -lt 3 ]; then exit 1; fi
  namespace="$1"
  secret="$2"
  key="$3"

  kubectl get secret "$secret" -n "$namespace" -o jsonpath="{.data.$key}" | base64 -d
}

secret_key_exists() {
  if [ "$#" -lt 3 ]; then exit 1; fi
  namespace="$1"
  secret="$2"
  key="$3"

  kubectl get secret "$secret" -n "$namespace" -o jsonpath="{.data.$key}" | grep -q .
}

# Patches one or more keys on an existing secret without touching the rest of
# its data. Usage: patch_secret_values <namespace> <secret> key=value [key=value...]
patch_secret_values() {
  if [ "$#" -lt 3 ]; then exit 1; fi
  namespace="$1"
  secret="$2"
  shift 2

  patch="{\"data\":{"
  first=true
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    encoded=$(printf '%s' "$value" | base64 | tr -d '\n')
    if [ "$first" = true ]; then
      first=false
    else
      patch+=","
    fi
    patch+="\"$key\":\"$encoded\""
  done
  patch+="}}"

  kubectl patch secret "$secret" -n "$namespace" --type=merge -p "$patch"
}

###############################
## Backup of current secrets ##
###############################

backup_patroni_secrets() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  info "Backing up current $PATRONI_SECRET and $APPUSER_SECRET into $BACKUP_SECRET"

  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would merge $PATRONI_SECRET + $APPUSER_SECRET data into $BACKUP_SECRET (annotated rotated-at=$timestamp)"
    return
  fi

  patroni_json=$(kubectl get secret "$PATRONI_SECRET" -n "$namespace" -o json)
  appuser_json=$(kubectl get secret "$APPUSER_SECRET" -n "$namespace" -o json)

  merged_data=$(jq -n \
    --argjson a "$(echo "$patroni_json" | jq '.data')" \
    --argjson b "$(echo "$appuser_json" | jq '.data')" \
    '$a * $b')

  kubectl create secret generic "$BACKUP_SECRET" \
    -n "$namespace" \
    --type=Opaque \
    --dry-run=client \
    -o json \
    --from-literal=placeholder=placeholder |
    jq --argjson data "$merged_data" '.data = $data | del(.data.placeholder)' |
    kubectl apply -f -

  kubectl annotate secret "$BACKUP_SECRET" -n "$namespace" \
    "rotated-at=$timestamp" --overwrite
}

###########################################
## psql execution against the leader pod ##
###########################################

# Returns the name of any currently existing patroni pod (used only to run
# read-only cluster-wide commands like `patronictl list`, which can be
# executed from any member of the cluster).
get_any_patroni_pod() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  # shellcheck disable=SC2046,SC2086
  set -- $(get_patroni_pod_names "$namespace")
  if [ "$#" -lt 1 ]; then
    error "No patroni pods found in $namespace"
    exit 1
  fi
  echo "$1"
}

# Resolves the pod that is currently the Patroni leader. Leadership can move
# to any pod in the StatefulSet (it is not pinned to sso-patroni-0), so this
# is re-resolved on every call rather than assumed.
get_patroni_leader_pod() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  any_pod=$(get_any_patroni_pod "$namespace")
  leader=$(kubectl -n "$namespace" exec "$any_pod" -- patronictl list -f json |
    jq -r '.[] | select(.Role == "Leader" or .Role == "master") | .Member' | head -n 1)

  if [ -z "$leader" ]; then
    error "Unable to determine the current patroni leader pod in $namespace"
    exit 1
  fi

  echo "$leader"
}

# Runs SQL via psql inside the *current* patroni leader pod (writes such as
# ALTER ROLE must go to the primary), authenticating with the given
# (current, not-yet-rotated) username/password. Password is passed via
# PGPASSWORD to the exec'd process rather than as a CLI argument.
#
# `dbname` defaults to "postgres" since role-level statements (ALTER ROLE,
# CREATE ROLE, DROP ROLE) are cluster-wide and don't depend on which database
# you're connected to. Statements that operate on database-local objects
# (REASSIGN OWNED BY, DROP OWNED BY) only affect the database you're
# currently connected to, so callers touching those must pass the actual
# target database explicitly.
run_psql() {
  if [ "$#" -lt 4 ]; then exit 1; fi
  namespace="$1"
  username="$2"
  password="$3"
  sql="$4"
  dbname="${5:-postgres}"

  leader=$(get_patroni_leader_pod "$namespace")

  kubectl exec -i -n "$namespace" "$leader" -- \
    env PGPASSWORD="$password" psql -h localhost -U "$username" -d "$dbname" -v ON_ERROR_STOP=1 <<SQL
$sql
SQL
}

# Runs a single-value/tuples-only SQL query (e.g. SELECT count(*) ...) and
# returns the raw, unformatted result - no headers/row-count footer to strip.
run_psql_query() {
  if [ "$#" -lt 4 ]; then exit 1; fi
  namespace="$1"
  username="$2"
  password="$3"
  sql="$4"
  dbname="${5:-postgres}"

  leader=$(get_patroni_leader_pod "$namespace")

  kubectl exec -i -n "$namespace" "$leader" -- \
    env PGPASSWORD="$password" psql -h localhost -U "$username" -d "$dbname" -v ON_ERROR_STOP=1 -tAc "$sql"
}

# Postgres roles are cluster-wide, but REASSIGN OWNED BY / DROP OWNED BY only
# affect the database you're connected to. A role's owned objects (tables,
# sequences, etc.) and granted privileges can live in any database in the
# cluster - most commonly, for this app, its own same-named database (e.g.
# Keycloak's appuser role owns objects in a database also named after it).
# `pg_shdepend` is a shared, cluster-wide catalog, so this single query
# (run against any database) finds every database where the role has an
# ownership or privilege dependency that must be cleaned up before it can be
# dropped.
get_databases_with_role_dependencies() {
  if [ "$#" -lt 3 ]; then exit 1; fi
  namespace="$1"
  role_name="$2"
  superuser_password="$3"

  sql="SELECT DISTINCT d.datname
FROM pg_shdepend sd
JOIN pg_database d ON sd.dbid = d.oid
JOIN pg_roles r ON sd.refobjid = r.oid
WHERE r.rolname = '$role_name' AND d.datname NOT IN ('template0', 'template1');"

  run_psql_query "$namespace" "$SUPERUSER_ROLE" "$superuser_password" "$sql"
}

#####################################
## System role password rotation   ##
#####################################

rotate_system_role_passwords() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  current_superuser_password=$(get_secret_value "$namespace" "$PATRONI_SECRET" "password-superuser")

  new_admin_password=$(generate_password 32)
  new_standby_password=$(generate_password 32)
  new_superuser_password=$(generate_password 32)

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would rotate passwords for roles: $ADMIN_ROLE, $STANDBY_ROLE, $SUPERUSER_ROLE"
    return
  fi

  info "Rotating admin/standby/superuser passwords in Postgres"

  # Superuser's own password is changed last in the same session; the already
  # authenticated connection stays valid for the remainder of the session.
  sql="ALTER ROLE \"$ADMIN_ROLE\" WITH PASSWORD '$new_admin_password';
ALTER ROLE \"$STANDBY_ROLE\" WITH PASSWORD '$new_standby_password';
ALTER ROLE \"$SUPERUSER_ROLE\" WITH PASSWORD '$new_superuser_password';"

  run_psql "$namespace" "$SUPERUSER_ROLE" "$current_superuser_password" "$sql"

  info "Updating $PATRONI_SECRET with the new passwords"
  patch_secret_values "$namespace" "$PATRONI_SECRET" \
    "password-admin=$new_admin_password" \
    "password-standby=$new_standby_password" \
    "password-superuser=$new_superuser_password"
}

########################################################
## Zero-downtime Patroni pod cycle (system creds only) ##
########################################################

get_patroni_pod_names() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  kubectl get pods -n "$namespace" -l app.kubernetes.io/name=sso-patroni -o jsonpath='{.items[*].metadata.name}'
}

restart_patroni_pod() {
  if [ "$#" -lt 2 ]; then exit 1; fi
  namespace="$1"
  pod="$2"

  info "Restarting patroni pod $pod"
  kubectl delete pod "$pod" -n "$namespace"
  wait_for_patroni_healthy "$namespace"
}

cycle_patroni_pods_zero_downtime() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would rolling-restart patroni pods (replicas first, leader last via patronictl switchover)"
    return
  fi

  leader=$(get_patroni_leader_pod "$namespace")
  info "Current patroni leader is $leader"

  replicas=""
  for pod in $(get_patroni_pod_names "$namespace"); do
    [ "$pod" == "$leader" ] && continue
    replicas="$replicas $pod"
  done

  # Restart replicas first so they pick up the new secret values.
  for pod in $replicas; do
    restart_patroni_pod "$namespace" "$pod"
  done

  # Hand leadership off gracefully to an already-restarted replica before
  # restarting the (still using old creds) former leader pod.
  candidate=$(echo "$replicas" | awk '{print $1}')
  if [ -n "$candidate" ]; then
    info "Switching patroni leadership from $leader to $candidate before restarting $leader"
    kubectl -n "$namespace" exec "$leader" -- \
      patronictl switchover --leader "$leader" --candidate "$candidate" --force
    wait_for_patroni_healthy "$namespace"
  fi

  restart_patroni_pod "$namespace" "$leader"
  wait_for_patroni_all_ready "$namespace"
}

#####################################
## Appuser (application) rotation  ##
#####################################

rotate_appuser_role() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  old_appuser_username=$(get_secret_value "$namespace" "$APPUSER_SECRET" "username-appuser1")
  new_appuser_username="appuser1-$(generate_rotation_suffix)"
  new_appuser_password=$(generate_password 32)

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would create new appuser role '$new_appuser_username' inheriting privileges from '$old_appuser_username'"
    return
  fi

  info "Creating new appuser role $new_appuser_username (inherits $old_appuser_username's privileges)"

  superuser_password=$(get_secret_value "$namespace" "$PATRONI_SECRET" "password-superuser")

  sql="CREATE ROLE \"$new_appuser_username\" WITH LOGIN PASSWORD '$new_appuser_password' IN ROLE \"$old_appuser_username\";"
  run_psql "$namespace" "$SUPERUSER_ROLE" "$superuser_password" "$sql"

  info "Verifying the new appuser role can authenticate"
  run_psql "$namespace" "$new_appuser_username" "$new_appuser_password" "SELECT 1;"

  info "Updating $APPUSER_SECRET with the new appuser role"
  patch_secret_values "$namespace" "$APPUSER_SECRET" \
    "username-appuser1=$new_appuser_username" \
    "password-appuser1=$new_appuser_password"

  # Remember the old role name so `finalize_appuser_rotation` (a separate,
  # explicitly-triggered later run) knows which role to retire.
  patch_secret_values "$namespace" "$BACKUP_SECRET" \
    "pending-old-appuser-role=$old_appuser_username"
}

finalize_appuser_rotation() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  old_appuser_username=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-old-appuser-role" 2>/dev/null)
  if [ -z "$old_appuser_username" ]; then
    warn "No pending appuser rotation found on $BACKUP_SECRET; nothing to finalize"
    return
  fi

  new_appuser_username=$(get_secret_value "$namespace" "$APPUSER_SECRET" "username-appuser1")
  superuser_password=$(get_secret_value "$namespace" "$PATRONI_SECRET" "password-superuser")

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would reassign ownership from '$old_appuser_username' to '$new_appuser_username' and drop the old role"
    return
  fi

  info "Checking for active sessions still using the old appuser role ($old_appuser_username)"
  active_sessions=$(run_psql_query "$namespace" "$SUPERUSER_ROLE" "$superuser_password" \
    "SELECT count(*) FROM pg_stat_activity WHERE usename = '$old_appuser_username';")

  if [[ "$active_sessions" =~ ^[0-9]+$ ]] && [ "$active_sessions" -gt 0 ]; then
    warn "There are still $active_sessions active session(s) using $old_appuser_username; aborting finalize. Re-run once consumers have fully cycled."
    exit 1
  fi

  # REASSIGN OWNED BY / DROP OWNED BY only affect the database you're
  # connected to, but the old role's actual owned objects (e.g. Keycloak's
  # tables) typically live in a same-named application database, not in
  # "postgres". Reassign/clean up ownership in every database the role has
  # a dependency in before dropping the (now cluster-wide) role itself.
  owned_databases=$(get_databases_with_role_dependencies "$namespace" "$old_appuser_username" "$superuser_password")

  if [ -z "$owned_databases" ]; then
    warn "No databases reported ownership/privilege dependencies for $old_appuser_username; proceeding directly to DROP ROLE"
  fi

  for db in $owned_databases; do
    info "Reassigning ownership from $old_appuser_username to $new_appuser_username in database $db"
    sql="REASSIGN OWNED BY \"$old_appuser_username\" TO \"$new_appuser_username\";
DROP OWNED BY \"$old_appuser_username\";"
    run_psql "$namespace" "$SUPERUSER_ROLE" "$superuser_password" "$sql" "$db"
  done

  info "Dropping the old appuser role $old_appuser_username"
  run_psql "$namespace" "$SUPERUSER_ROLE" "$superuser_password" "DROP ROLE \"$old_appuser_username\";"

  kubectl patch secret "$BACKUP_SECRET" -n "$namespace" --type=json \
    -p='[{"op": "remove", "path": "/data/pending-old-appuser-role"}]' || true
}

#####################################
## Consumer cycling (Keycloak etc) ##
#####################################

cycle_keycloak_pods() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would restart the sso-keycloak StatefulSet so it picks up the new appuser secret values"
    return
  fi

  info "Cycling Keycloak pods so they pick up the new appuser credentials"
  kubectl rollout restart statefulset/sso-keycloak -n "$namespace"
  wait_for_keycloak_all_ready "$namespace"
}

# The backupcontainer is deployed via Helm as `sso-backup-18`, but the actual
# pods run under a separate Deployment named `sso-backup-storage-18`. Note the
# "-18" suffix is tied to this specific Helm release/chart version - if that
# release is ever bumped/renamed, this resource name will need updating too.
cycle_backupcontainer_pod() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"
  dry_run="${2:-true}"

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would restart deployment/sso-backup-storage-18 so it picks up the new appuser secret values"
    return
  fi

  info "Cycling the backupcontainer pod (deployment/sso-backup-storage-18) so it picks up the new appuser credentials"
  kubectl rollout restart deployment/sso-backup-storage-18 -n "$namespace"
  kubectl rollout status deployment/sso-backup-storage-18 -n "$namespace" --timeout=300s
}

# Grafana may also need its deployed pods cycled to pick up new credentials.
# Left commented out as a reminder until this is confirmed to be in scope:
# Currently this depends of a CICD refactor of grafana deployments
# cycle_grafana_pods() {
#   namespace="$1"
#   kubectl rollout restart deployment/grafana -n "$namespace"
# }
