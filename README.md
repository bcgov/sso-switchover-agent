# sso-switchover-agent

Switchover Agent in the Disaster Recovery Scenario between Gold &amp; Golddr. The workflow is heavily inspired by `API Gateway Team`'s [Switchover Agent](https://github.com/bcgov/switchover-agent).

## Scripts

There are five scripts in [transition-scripts](./transition-scripts) to provision a set of Keycloak deployments in Gold & Golddr clusters in different scenarios.
As a common step, please check the version of the Keycloak Helm chart to ensure it is the desired one.

### deploy.sh

It deployes Keycloak resources in the target namespaces in a normal situation and sets "active" mode in Gold cluster and "standby" mode in Golddr cluster.
It upgrades the current Helm deployments if there are existing Helm deployments, otherwise it installs them.

```sh
cd transition-scripts
deploy.sh <namespace>
```

### destroy.sh

It destroyes Keycloak resources in the target namespaces in Gold & Golddr.

```sh
cd transition-scripts
destroy.sh <namespace>
```

### switch-to-golddr.sh

It sets the target namespace of the Golddr cluster active, and the corresponding Gold cluster standby.
This workflow is designed to run in the status of the Gold cluster's failover.

```sh
cd transition-scripts
switch-to-golddr.sh <namespace>
```

### switch-to-gold.sh

It sets the target namespace of the Gold cluster active, and the corresponding Golddr cluster standby.
This workflow is designed to run in the recovery stage of the Gold cluster's failover.

```sh
cd transition-scripts
switch-to-gold.sh <namespace>
```
