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
## Retry / resilience helpers        ##
#######################################

# Connectivity to the cluster API can drop mid-run (transient DNS blips,
# brief apiserver unavailability, etc.) - see credential-rotation/README.md
# for why simply re-running the whole action from scratch after that isn't
# always safe. These are overridable via env vars for testing.
ROTATE_RETRY_ATTEMPTS="${ROTATE_RETRY_ATTEMPTS:-5}"
ROTATE_RETRY_DELAY_SECONDS="${ROTATE_RETRY_DELAY_SECONDS:-5}"

# Retries a command a few times with a short delay in between, so a
# transient connectivity blip doesn't fail an entire rotation step outright.
# Only the *successful* attempt's stdout is ever emitted - a failed attempt's
# (possibly partial) stdout is discarded so it can never corrupt a caller
# capturing this via command substitution. Retry/failure messages go straight
# to stderr (not the shared info/warn/error helpers, which print to stdout)
# for the same reason.
#
# Usage: with_retry "<description for log messages>" <command> [args...]
with_retry() {
  description="$1"
  shift

  attempt=1
  while true; do
    if output=$("$@"); then
      printf '%s\n' "$output"
      return 0
    fi

    if [ "$attempt" -ge "$ROTATE_RETRY_ATTEMPTS" ]; then
      echo "[retry] $description failed after $ROTATE_RETRY_ATTEMPTS attempts; giving up" >&2
      return 1
    fi

    echo "[retry] $description failed (attempt $attempt/$ROTATE_RETRY_ATTEMPTS); retrying in ${ROTATE_RETRY_DELAY_SECONDS}s" >&2
    sleep "$ROTATE_RETRY_DELAY_SECONDS"
    attempt=$((attempt + 1))
  done
}

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

  with_retry "getting $secret/$key in $namespace" \
    kubectl get secret "$secret" -n "$namespace" -o jsonpath="{.data.$key}" | base64 -d
}

secret_key_exists() {
  if [ "$#" -lt 3 ]; then exit 1; fi
  namespace="$1"
  secret="$2"
  key="$3"

  with_retry "getting $secret/$key in $namespace" \
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

  with_retry "patching secret $secret in $namespace" \
    kubectl patch secret "$secret" -n "$namespace" --type=merge -p "$patch" >/dev/null
}

# Removes one or more keys from a secret's data (a merge patch can only add/
# overwrite keys - only a JSON patch "remove" op can delete one). Missing
# keys make the "remove" op itself fail, so this tolerates that (the key
# being absent already is the desired end state) rather than treating it as
# an error worth retrying/failing on.
remove_secret_keys() {
  if [ "$#" -lt 2 ]; then exit 1; fi
  namespace="$1"
  secret="$2"
  shift 2

  ops="["
  first=true
  for key in "$@"; do
    if [ "$first" = true ]; then
      first=false
    else
      ops+=","
    fi
    ops+="{\"op\":\"remove\",\"path\":\"/data/$key\"}"
  done
  ops+="]"

  kubectl patch secret "$secret" -n "$namespace" --type=json -p="$ops" >/dev/null 2>&1 || true
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

  patroni_json=$(with_retry "getting $PATRONI_SECRET in $namespace" \
    kubectl get secret "$PATRONI_SECRET" -n "$namespace" -o json)
  appuser_json=$(with_retry "getting $APPUSER_SECRET in $namespace" \
    kubectl get secret "$APPUSER_SECRET" -n "$namespace" -o json)

  merged_data=$(jq -n \
    --argjson a "$(echo "$patroni_json" | jq '.data')" \
    --argjson b "$(echo "$appuser_json" | jq '.data')" \
    '$a * $b')

  # --dry-run=client only builds the manifest locally, it doesn't touch the
  # API server, so it doesn't need retrying. The manifest is written to a
  # temp file (rather than piped directly) so `kubectl apply` below can be
  # retried and re-read the same content on every attempt - a pipe's stdin
  # would otherwise only be readable once.
  manifest_file=$(mktemp)
  kubectl create secret generic "$BACKUP_SECRET" \
    -n "$namespace" \
    --type=Opaque \
    --dry-run=client \
    -o json \
    --from-literal=placeholder=placeholder |
    jq --argjson data "$merged_data" '.data = $data | del(.data.placeholder)' \
    >"$manifest_file"

  with_retry "creating/updating $BACKUP_SECRET in $namespace" \
    kubectl apply -f "$manifest_file" >/dev/null

  with_retry "annotating $BACKUP_SECRET in $namespace" \
    kubectl annotate secret "$BACKUP_SECRET" -n "$namespace" \
    "rotated-at=$timestamp" --overwrite >/dev/null

  rm -f "$manifest_file"
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
  raw=$(with_retry "querying patronictl list via $any_pod in $namespace" \
    kubectl -n "$namespace" exec "$any_pod" -- patronictl list -f json)
  leader=$(echo "$raw" | jq -r '.[] | select(.Role == "Leader" or .Role == "master") | .Member' | head -n 1)

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

  # Retries on failure (transient connectivity blips) with its own loop
  # rather than delegating to with_retry directly, since the SQL is piped in
  # via heredoc rather than passed as a plain argument, and leadership may
  # have moved mid-retry (e.g. if a switchover partially completed), so the
  # leader pod is re-resolved on every attempt rather than reused.
  attempt=1
  while true; do
    if kubectl exec -i -n "$namespace" "$leader" -- \
      env PGPASSWORD="$password" psql -h localhost -U "$username" -d "$dbname" -v ON_ERROR_STOP=1 <<SQL
$sql
SQL
    then
      return 0
    fi

    if [ "$attempt" -ge "$ROTATE_RETRY_ATTEMPTS" ]; then
      echo "[retry] running psql against $namespace/$leader failed after $ROTATE_RETRY_ATTEMPTS attempts; giving up" >&2
      return 1
    fi

    echo "[retry] running psql against $namespace/$leader failed (attempt $attempt/$ROTATE_RETRY_ATTEMPTS); retrying in ${ROTATE_RETRY_DELAY_SECONDS}s" >&2
    sleep "$ROTATE_RETRY_DELAY_SECONDS"
    attempt=$((attempt + 1))
    leader=$(get_patroni_leader_pod "$namespace")
  done
}

# Runs a single-value/tuples-only SQL query (e.g. SELECT count(*) ...) and
# returns the raw, unformatted result - no headers/row-count footer to strip.
# See run_psql's comment above for why this has its own retry loop instead of
# using with_retry directly.
run_psql_query() {
  if [ "$#" -lt 4 ]; then exit 1; fi
  namespace="$1"
  username="$2"
  password="$3"
  sql="$4"
  dbname="${5:-postgres}"

  leader=$(get_patroni_leader_pod "$namespace")

  attempt=1
  while true; do
    if output=$(kubectl exec -i -n "$namespace" "$leader" -- \
      env PGPASSWORD="$password" psql -h localhost -U "$username" -d "$dbname" -v ON_ERROR_STOP=1 -tAc "$sql"); then
      printf '%s\n' "$output"
      return 0
    fi

    if [ "$attempt" -ge "$ROTATE_RETRY_ATTEMPTS" ]; then
      echo "[retry] running psql query against $namespace/$leader failed after $ROTATE_RETRY_ATTEMPTS attempts; giving up" >&2
      return 1
    fi

    echo "[retry] running psql query against $namespace/$leader failed (attempt $attempt/$ROTATE_RETRY_ATTEMPTS); retrying in ${ROTATE_RETRY_DELAY_SECONDS}s" >&2
    sleep "$ROTATE_RETRY_DELAY_SECONDS"
    attempt=$((attempt + 1))
    leader=$(get_patroni_leader_pod "$namespace")
  done
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

# `IN ROLE` (used by rotate_appuser_role to create the new role) only grants
# access via *inherited role membership* - it is not a substitute for the old
# role's own direct database-level ACL entries (e.g. `GRANT CONNECT, CREATE
# ON DATABASE ... TO old_role`). REASSIGN OWNED BY / DROP OWNED BY (run later
# by finalize_appuser_rotation) only move object ownership and revoke
# privileges *granted to* the old role - they never copy those direct grants
# onto the new role. So once the old role is dropped, any privilege the new
# role only had by inheriting through membership in the old role disappears
# with it. This queries every database's ACL (via aclexplode) for privileges
# explicitly granted directly to the given role, returning
# "datname|privilege_type" pairs (one per line) so the caller can replicate
# them onto the new role with real GRANT statements before the old role is
# ever dropped.
get_database_grants_for_role() {
  if [ "$#" -lt 3 ]; then exit 1; fi
  namespace="$1"
  role_name="$2"
  superuser_password="$3"

  sql="SELECT d.datname || '|' || acl.privilege_type
FROM pg_database d, aclexplode(d.datacl) acl
JOIN pg_roles r ON acl.grantee = r.oid
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

  if [ "$dry_run" = "true" ]; then
    info "[dry-run] would rotate passwords for roles: $ADMIN_ROLE, $STANDBY_ROLE, $SUPERUSER_ROLE"
    return
  fi

  # Resume-safe: if a previous attempt already generated and recorded
  # pending passwords (e.g. it got interrupted after ALTER ROLE succeeded
  # but before $PATRONI_SECRET was updated to match), reuse those same
  # values instead of generating brand-new random ones on retry - ALTER ROLE
  # to the same password twice is a harmless no-op, so this converges
  # regardless of exactly where the previous attempt failed.
  pending_admin=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-password-admin" 2>/dev/null || true)
  pending_standby=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-password-standby" 2>/dev/null || true)
  pending_superuser=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-password-superuser" 2>/dev/null || true)

  if [ -n "$pending_admin" ] && [ -n "$pending_standby" ] && [ -n "$pending_superuser" ]; then
    info "Resuming an in-progress system-role password rotation from previously recorded pending values"
    new_admin_password="$pending_admin"
    new_standby_password="$pending_standby"
    new_superuser_password="$pending_superuser"
  else
    new_admin_password=$(generate_password 32)
    new_standby_password=$(generate_password 32)
    new_superuser_password=$(generate_password 32)

    info "Recording planned admin/standby/superuser passwords before mutating, so a retry can resume safely"
    patch_secret_values "$namespace" "$BACKUP_SECRET" \
      "pending-password-admin=$new_admin_password" \
      "pending-password-standby=$new_standby_password" \
      "pending-password-superuser=$new_superuser_password"
  fi

  info "Rotating admin/standby/superuser passwords in Postgres"

  # Superuser's own password is changed last in the same session; the already
  # authenticated connection stays valid for the remainder of the session.
  sql="ALTER ROLE \"$ADMIN_ROLE\" WITH PASSWORD '$new_admin_password';
ALTER ROLE \"$STANDBY_ROLE\" WITH PASSWORD '$new_standby_password';
ALTER ROLE \"$SUPERUSER_ROLE\" WITH PASSWORD '$new_superuser_password';"

  # If a previous attempt got far enough to actually change the superuser's
  # own password before failing, $current_superuser_password (read from the
  # not-yet-updated secret) will no longer authenticate. Fall back to the
  # pending (already-generated) superuser password in that case rather than
  # failing outright.
  if ! run_psql "$namespace" "$SUPERUSER_ROLE" "$current_superuser_password" "$sql"; then
    if [ -n "$pending_superuser" ] && [ "$pending_superuser" != "$current_superuser_password" ]; then
      warn "Could not authenticate with the current superuser password; a previous attempt may have already rotated it - retrying with the pending password"
      run_psql "$namespace" "$SUPERUSER_ROLE" "$pending_superuser" "$sql"
    else
      error "Failed to rotate system role passwords in $namespace"
      exit 1
    fi
  fi

  info "Updating $PATRONI_SECRET with the new passwords"
  patch_secret_values "$namespace" "$PATRONI_SECRET" \
    "password-admin=$new_admin_password" \
    "password-standby=$new_standby_password" \
    "password-superuser=$new_superuser_password"

  info "Clearing resumable rotation state now that the passwords are live"
  remove_secret_keys "$namespace" "$BACKUP_SECRET" \
    "pending-password-admin" "pending-password-standby" "pending-password-superuser"
}

########################################################
## Zero-downtime Patroni pod cycle (system creds only) ##
########################################################

get_patroni_pod_names() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  with_retry "listing patroni pods in $namespace" \
    kubectl get pods -n "$namespace" -l app.kubernetes.io/name=sso-patroni -o jsonpath='{.items[*].metadata.name}'
}

restart_patroni_pod() {
  if [ "$#" -lt 2 ]; then exit 1; fi
  namespace="$1"
  pod="$2"

  info "Restarting patroni pod $pod"
  # --ignore-not-found makes this safe to retry: if the delete already
  # succeeded but the confirmation was lost to a network blip, retrying
  # against an already-gone pod is a no-op instead of an error.
  with_retry "deleting pod $pod in $namespace" \
    kubectl delete pod "$pod" -n "$namespace" --ignore-not-found >/dev/null
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
    with_retry "patronictl switchover $leader -> $candidate in $namespace" \
      kubectl -n "$namespace" exec "$leader" -- \
      patronictl switchover --leader "$leader" --candidate "$candidate" --force >/dev/null
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

  if [ "$dry_run" = "true" ]; then
    old_appuser_username=$(get_secret_value "$namespace" "$APPUSER_SECRET" "username-appuser1")
    new_appuser_username="appuser1-$(generate_rotation_suffix)"
    info "[dry-run] would create new appuser role '$new_appuser_username' inheriting privileges from '$old_appuser_username'"
    return
  fi

  superuser_password=$(get_secret_value "$namespace" "$PATRONI_SECRET" "password-superuser")

  # Resume-safe: if a previous attempt already recorded a planned old/new
  # appuser pair (e.g. it got interrupted after CREATE ROLE succeeded but
  # before $APPUSER_SECRET was updated to point at it), reuse that same
  # identity instead of generating a brand-new one on retry - otherwise every
  # retry would create and then abandon (orphan) yet another role. A stale
  # pending pair left over from an already-fully-completed rotation (i.e. the
  # "new" role is already the one live in $APPUSER_SECRET) is detected and
  # cleared instead of being reused, so a genuinely new rotation run doesn't
  # silently no-op by "resuming" old finished state.
  current_appuser_username=$(get_secret_value "$namespace" "$APPUSER_SECRET" "username-appuser1")
  pending_old=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-new-appuser-old-username" 2>/dev/null || true)
  pending_new=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-new-appuser-username" 2>/dev/null || true)
  pending_password=$(get_secret_value "$namespace" "$BACKUP_SECRET" "pending-new-appuser-password" 2>/dev/null || true)

  if [ -n "$pending_new" ] && [ "$pending_new" = "$current_appuser_username" ]; then
    info "Clearing stale pending appuser rotation state left over from an already-completed run"
    remove_secret_keys "$namespace" "$BACKUP_SECRET" \
      "pending-new-appuser-old-username" "pending-new-appuser-username" "pending-new-appuser-password"
    pending_new=""
  fi

  if [ -n "$pending_new" ]; then
    info "Resuming an in-progress appuser rotation ($pending_old -> $pending_new)"
    old_appuser_username="$pending_old"
    new_appuser_username="$pending_new"
    new_appuser_password="$pending_password"
  else
    old_appuser_username="$current_appuser_username"
    new_appuser_username="appuser1-$(generate_rotation_suffix)"
    new_appuser_password=$(generate_password 32)

    info "Recording planned appuser rotation ($old_appuser_username -> $new_appuser_username) before mutating, so a retry can resume safely"
    patch_secret_values "$namespace" "$BACKUP_SECRET" \
      "pending-new-appuser-old-username=$old_appuser_username" \
      "pending-new-appuser-username=$new_appuser_username" \
      "pending-new-appuser-password=$new_appuser_password"
  fi

  info "Creating new appuser role $new_appuser_username (inherits $old_appuser_username's privileges)"

  # CREATE-OR-ALTER (rather than plain CREATE ROLE): safe to re-run if a
  # previous attempt already created the role but failed before later steps
  # completed. GRANT membership is reasserted unconditionally too - also a
  # harmless no-op if it's already in place.
  sql="DO \$rotate_appuser\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$new_appuser_username') THEN
    CREATE ROLE \"$new_appuser_username\" WITH LOGIN PASSWORD '$new_appuser_password' IN ROLE \"$old_appuser_username\";
  ELSE
    ALTER ROLE \"$new_appuser_username\" WITH PASSWORD '$new_appuser_password';
  END IF;
END
\$rotate_appuser\$;
GRANT \"$old_appuser_username\" TO \"$new_appuser_username\";"
  run_psql "$namespace" "$SUPERUSER_ROLE" "$superuser_password" "$sql"

  # `IN ROLE` only gives the new role access via *inherited membership* in
  # the old role. That's fine while both roles co-exist, but
  # finalize_appuser_rotation() later drops the old role outright, which
  # would silently take any database-level privilege (e.g. CONNECT/CREATE)
  # the new role only had *through that membership* down with it. Mirror the
  # old role's own direct database-level grants onto the new role now, as
  # real independent GRANTs, so its access doesn't depend on the old role
  # continuing to exist.
  database_grants=$(get_database_grants_for_role "$namespace" "$old_appuser_username" "$superuser_password")
  if [ -n "$database_grants" ]; then
    info "Mirroring $old_appuser_username's direct database-level grants onto $new_appuser_username"
    while IFS='|' read -r dbname privilege; do
      [ -z "$dbname" ] && continue
      run_psql "$namespace" "$SUPERUSER_ROLE" "$superuser_password" \
        "GRANT $privilege ON DATABASE \"$dbname\" TO \"$new_appuser_username\";"
    done <<< "$database_grants"
  fi

  info "Verifying the new appuser role can authenticate"
  run_psql "$namespace" "$new_appuser_username" "$new_appuser_password" "SELECT 1;"

  info "Updating $APPUSER_SECRET with the new appuser role"
  patch_secret_values "$namespace" "$APPUSER_SECRET" \
    "username-appuser1=$new_appuser_username" \
    "password-appuser1=$new_appuser_password"

  # Record the old role name so `finalize_appuser_rotation` (a separate,
  # explicitly-triggered later run) knows which role to retire, and clear the
  # now-resolved pending-new-* resume state in the same call so there's no
  # window where a retry could misinterpret it as still in-flight.
  old_appuser_b64=$(printf '%s' "$old_appuser_username" | base64 | tr -d '\n')
  with_retry "recording old appuser role + clearing pending rotation state in $namespace" \
    kubectl patch secret "$BACKUP_SECRET" -n "$namespace" --type=json -p="[
      {\"op\":\"add\",\"path\":\"/data/pending-old-appuser-role\",\"value\":\"$old_appuser_b64\"},
      {\"op\":\"remove\",\"path\":\"/data/pending-new-appuser-old-username\"},
      {\"op\":\"remove\",\"path\":\"/data/pending-new-appuser-username\"},
      {\"op\":\"remove\",\"path\":\"/data/pending-new-appuser-password\"}
    ]" >/dev/null
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
  run_psql "$namespace" "$SUPERUSER_ROLE" "$superuser_password" "DROP ROLE IF EXISTS \"$old_appuser_username\";"

  remove_secret_keys "$namespace" "$BACKUP_SECRET" "pending-old-appuser-role"
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
  with_retry "rollout restart statefulset/sso-keycloak in $namespace" \
    kubectl rollout restart statefulset/sso-keycloak -n "$namespace" >/dev/null
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
  with_retry "rollout restart deployment/sso-backup-storage-18 in $namespace" \
    kubectl rollout restart deployment/sso-backup-storage-18 -n "$namespace" >/dev/null
  with_retry "rollout status deployment/sso-backup-storage-18 in $namespace" \
    kubectl rollout status deployment/sso-backup-storage-18 -n "$namespace" --timeout=300s >/dev/null
}

# Grafana may also need its deployed pods cycled to pick up new credentials.
# Left commented out as a reminder until this is confirmed to be in scope:
# Currently this depends of a CICD refactor of grafana deployments
# cycle_grafana_pods() {
#   namespace="$1"
#   kubectl rollout restart deployment/grafana -n "$namespace"
# }
