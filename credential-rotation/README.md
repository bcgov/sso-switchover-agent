# Gold Patroni credential rotation

This directory contains the scripts backing the **Rotate Gold Patroni
credentials** GitHub Action (`.github/workflows/rotate-credentials.yml`). It
rotates the Patroni system credentials (`admin`, `standby`, `superuser` — the
`sso-patroni` secret) and the Keycloak application credential (`appuser1` —
the `sso-patroni-appusers` secret) for the **Gold cluster only**, with zero
downtime. GoldDR is out of scope for this feature.

## Why this is two steps (rotate, then finalize)

PostgreSQL doesn't support a role having two valid passwords at the same time.
To give a safe grace period for the appuser credential (so a slow-to-restart
consumer using the old password isn't broken mid-rotation), rotation works as
a **role swap** instead:

1. **Rotate** (default mode) creates a brand-new login role (new username
   *and* password) that is granted membership in the old role
   (`GRANT <old_role> TO <new_role>`), so both the old and new roles remain
   valid simultaneously. `sso-patroni-appusers` is updated to point at the new
   role, and Keycloak (and, once wired up, backupcontainer) are cycled to pick
   it up. The old role is **not** touched.
2. **Finalize** (`finalize_appuser_rotation: true`, run later as a separate
   workflow run once the team has confirmed the new credential is in use
   everywhere) checks that no active Postgres sessions still use the old
   role, then reassigns ownership of any objects it owns to the new role and
   drops it.

The admin/standby/superuser passwords don't need this two-phase treatment —
they're only used internally by Patroni itself, so a straight password change
followed by a rolling pod restart (replicas first, graceful `patronictl
switchover`, old leader last) is sufficient for zero downtime.

## Running it

Via the **Rotate Gold Patroni credentials** action in GitHub:

- `project`: `SANDBOX` or `PRODUCTION`
- `environment`: `dev`, `test`, or `prod`
- `dry_run`: defaults to `true` — prints the planned actions (generated
  *usernames* only, never passwords) without mutating anything. Always run
  with `dry_run: true` first.
- `finalize_appuser_rotation`: defaults to `false`. Set to `true` on a later,
  separate run to drop the old appuser role once you've confirmed the new
  credential works everywhere.

Locally (must already be logged into the Gold cluster):

```sh
cd credential-rotation
./rotate-credentials.sh <namespace> --dry-run
./rotate-credentials.sh <namespace> --no-dry-run
./rotate-credentials.sh <namespace> --no-dry-run --finalize
```

For now we will run these locally.  Run in dev, test, prod, then manually update the grafana credentials before running the finalizing step.  Make sure to set DR to standby to ensure replication works.



## Rollback

Before making any change, the current `sso-patroni` and
`sso-patroni-appusers` secret data is merged into a backup secret,
`sso-patroni-old-creds` (annotated with a `rotated-at` timestamp). If a
rotation fails partway through:

1. Restore the previous values from `sso-patroni-old-creds` into `sso-patroni`
   / `sso-patroni-appusers` (`kubectl patch secret ... --type=merge`, or
   `kubectl edit secret`).
2. Re-run the same zero-downtime pod cycle used by this script (rolling
   restart of patroni pods, then Keycloak) so the running processes pick the
   restored values back up.
3. If the appuser role rotation had already created the new role, it's safe
   to leave it in place (it's a normal, valid Postgres role) or drop it
   manually once you've confirmed it's unused.

## Known open items

- **`patroni.additionalCredentials` chart behavior is unverified.** The
  `sso-patroni` Helm chart is hosted outside this repo. This script
  deliberately avoids running `helm upgrade` for the appuser rotation step and
  instead manages the role directly via SQL + a plain secret patch, because if
  that chart declaratively reconciles `additionalCredentials` and drops DB
  roles missing from its values, a `helm upgrade` here could prematurely
  delete the *old* appuser role before the finalize step. Confirm the chart's
  actual behavior (e.g. by testing in a sandbox namespace) before changing
  this to use `helm upgrade`.
- **`SUPERUSER_ROLE` / `ADMIN_ROLE` / `STANDBY_ROLE` role names** in
  `helpers/rotate.sh` are assumed to be `postgres`, `admin`, and `standby`
  respectively, matching the `sso-patroni` secret's key suffixes. Override via
  environment variables if the real role names differ.
- **`cycle_backupcontainer_pod`** restarts `deployment/sso-backup-storage-18`
  (the backupcontainer's pods, deployed via the `sso-backup-18` Helm release).
  The `-18` suffix is tied to that specific release/chart version — if it's
  ever bumped or renamed, this resource name will need updating too.
- **Grafana** may also need its pods cycled to pick up new credentials; a
  commented-out reminder function is left in `helpers/rotate.sh`.
