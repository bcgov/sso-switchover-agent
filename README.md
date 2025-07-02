# sso-switchover-agent

![Lifecycle:Stable](https://img.shields.io/badge/Lifecycle-Stable-97ca00)

Switchover Agent in the Disaster Recovery Scenario between Gold &amp; Golddr. The workflow is heavily inspired by `API Gateway Team`'s [Switchover Agent](https://github.com/bcgov/switchover-agent).

## Pipeline

The current pipeline documentation for using this repos to deploy the Keycloak app is documented in the private discussion [here](https://github.com/bcgov-c/pathfinder-sso-docs/discussions/201).
## Using switchover agent as a deployment tool.

In addition to the disaster recovery (switchover) agent, the keycloak deployment in gold is managed through the scripts in this repo. The deployment can be triggered in a local dev environment using [this](./transition-scripts/deploy.sh) script, or using the "Deploy Keycloak resources in Gold & Golddr" action in the github repo.

The Keycloak deployments in Gold and Gold DR are manage by helm, in the `transition-scripts/` directory.  This is where you will find the deployment values.  The helm chart version is set by `KEYCLOAK_HELM_CHART_VERSION` variable in the `transition-scripts/helpers/helm.sh` file.  It will need to be updated for the actions to deploy a new version of the helm chart.

On a fresh deployment to gold the sso-keycloak-otp-credentials secret will be generated with null values.  One must update these with the relevant credentials, then re-run helm deployment.  After that the secret's values will be copied to the dr environments when helm sets the app in standby.

### Triggering the deployments/transitions locally

The local deployment workflow is an option if keycloak needs to be redeployed and github actions are down.  It is also a useful workflow when making changes to the helm charts.   Deploying changes directly to the sandbox environment is easier and less time intensive than requiring a code review and merging a PR. See [Local dev environment set up](#local-development-environment) and [Scripts](#scripts) documentation.

**Developer Note**: When deploying client facing apps from a local environment it is crucial to have the branch up to date with remote the `dev`.  If the image tag in `/transition-scripts/values/values.yaml` does not match the image tag on the remote dev branch, the keycloak image will revert the next time the github action is triggered.

### Triggering the deployments/transisions in github

The github actions found [here](.github/workflows) can be triggered manually in the repo.  The actions allow a user to deploy the resources in gold and gold dr, set dr to active, and set gold to active.  These require the target namespace and deployment branch as inputs.


## Triggering a preemptive failover

The GitHub action `Schedule Preemptive Failover` allows us to schedule sending traffic to the GoldDR cluster. This ensures a service outage of no more than a few seconds.  This can be used when an outage to the Gold cluster is expected or scheduled.  Note that only one outage can be scheduled at a time.

The job is manually triggered by choosing the environment (PRODUCTION, SANDBOX) and (dev, test, prod).  Then setting the start and end time for when traffic is to be sent to the GoldDR cluster `YYYY/MM/DD HH:MM`. When the failback occurs (after the end time) a dev will need to manually put the GoldDR deployment back into standby mode using the action `Set the DR deployment to standby`.

## The switchover agent

The switchover agent is deployed in the Gold DR namespace for a given project and watches changes in the DNS record.  If it detects the change it will automatically trigger the failover to the DR cluster.

The switchover agent app is built and deployed automatically on pr merges to `dev` and `main` using the action `publish-image.yml`.  On merging to the `dev` branch, the app is deployed to the Gold DR sandbox `dev` namespace.  On merging to the `main` branch, the app is built and deployed to the Gold DR production `dev`, `test`, and `prod` namespaces.

**Note 1**: the switchover agent runs transitions scripts against the `main` branch code, not the `dev` branch in the production environment.

**Note 2**: While the image updates and the helm chart is upgraded, the switchover agent pod must be scaled down and back up to make use of the new image.

The history of times the switchover agent has been triggered can be seen by looking at the history of the `Set the dr deployment to active` action in this repo.

### Configuring the openshift environment

In the gold dr namespace create the `sso-switchover-agent` secret, and configer the relevant environment variables. See [Environment Variables Documentation](./environment-variables.md).

### Turning off automatic failover

To prevent the switchover agent from automatically tirggering a build, it is best to alter the namespace in the `sso-switchover-agent` secret in the Gold DR repos.  This will trigger the "set the dr deployment to active" action for a non-existant namespace. Preventing an unwanted automated failover.

This does not block the team from manually triggering a failover through GitHub actions, or from the local development environment.

### DNS rerouting

The DNS rerouting is handled by the a golobal server load balancer (GSLB) that monitors the keycloak health endpoint `https://loginproxy.gov.bc.ca/auth/realms/master/.well-known/openid-configuration` and, if it is not accessible, the GSLB will redirect traffic to the Gold DR cluster app.

The Switchover agent monitors the keycloak app url (loginproxy.gov.bc.ca for production) and checks  every 5 seconds if the DNS record has changed. If it has, that indicates GSLB is redirecting to DR and the 'switch to dr' github action is triggered.

### The GSLB

Global server load balancing or GSLB is the practice of distributing Internet traffic amongst a large number of connected servers dispersed around multiple clusters. The benefits of GSLB include increased reliability, reductions in latency, and it promotes high availability.

Currently the GSLB is configured in such a way that when the gold health endpoint is up, traffic will be sent there.  If Gold's health endpoint does not return `200 OK`, the GSLB will point traffic at Gold DR.  If the Gold DR health check endpoint also fails, the GSLB will not route the traffic to either cluster, returning `SERVFAIL`. (The switchover agent logs this as `no DNS response`).  A side effect is that traffic automatically returns to Gold as soon as the Gold health check passes, the status of Gold DR has no impact on that redirection.

The state of the health check endpoint can be evaluated by running a curl command against the Gold and GoldDR clusters.  Documented internally [here](https://github.com/bcgov-c/pathfinder-sso-docs/discussions/80).

## Local development environment

As with most sso team repos the switchover agent uses the asdf tool for local package management.  The sso-keycloak [Developer Guidelines](https://github.com/bcgov/sso-keycloak/blob/dev/docs/developer-guide.md) provide the steps needed to set up and install the local tools.

For the switchover scripts to work the user must provide service credentials for both Gold and GoldDr.  To set this up locally, copy the `.env-example` file in the `transition-scripts` folder and rename it `.env`.

To retrieve the tokens, log into the Gold cluster and retrieve the `sso-action-deployer-######-token` token.  The `######` is the licence plate for the production or sandbox namespaces:

```
oc -n <<prod production/sandbox namespace>> get secrets | grep sso-action-deployer-######-token
oc -n <<prod production/sandbox namespace>> get secrets/sso-action-deployer-######-token-##### --template="{{.data.token|base64decode}}"
```

Repeat for the GoldDR cluster.


Lastly run the `login-and-test-local-connection.sh` script in the `transition-scripts` directory:

```
./login-and-test-local-connection.sh <<namespace>>
```

This script will login and attempt to switch context between Gold and GoldDR.  If it fails, most of the transition/deployment scripts will have issues running.  The one exception is `switch-to-golddr.sh`. Which is designed to be run even when the Gold cluster is down.

## Disaster recovery workflow

### When gold goes down

When and outage occurs, and the switchover agent is on, the `switch-to-golddr.sh` script will trigger.  Setting gold-dr database to `Active` and spinning up the keycloak-dr instance.  It will take about 10 to 15 minutes for keycloak to be back up and running.

If this script does not trigger you will have to do it manually either through github actions or your local development environment. Whether you trigger the scripts locally or through actions, the workflow is the same. The action is `Set the dr deployment to active`, the script is documented [below](#switch-to-golddr.sh).

### When gold is restored

When keycloak comes back online in Gold and passes the health check, the GSLB will immediately send traffic back to the Gold cluster.  Any changes made to the database while traffic was sent to the GoldDR cluster will be lost.

To put the GoldDr deployment back in standby mode we can run the action "Set the DR deployment to standby". This will put up the GoldDr maintenance page and synch patroni-DR to the patroni-Gold leader.

There may be issues with synching the transaction logs (`xlogs`).  If that occurs, run the action again with the `deletePVC` option checked. It will delete all PVCs and config in the GoldDR namespace.

#### State conflict

**THIS IS NO LONGER PART OF THE STANDARD WORKFLOW SINCE PATRONI-GOLD IS NOT PUT IN STANDBY MODE**

Even if patroni-gold is not in standby mode, the `switch-to-gold.sh`script is designed to handle that case.  It will put gold into standby mode to get the latest changes, then switch gold to the active cluster.   If this fails it may be necessary to delete the gold patroni deployment and recreate it in standby mode following the patroni-dr cluster.

Step 0.) Confirm Patroni-DR is up, healthy and **not** in standby mode.

Step 1.) Run the backup script on Patroni-Gold.

Step 2.) Scale the Patroni-Gold pods to zero

Step 3.) Delete all local config contexts. Not doing this can break the context switching in the scripts.  It is possible for there to be a lot of contexts that need deleting.
```
kubectl config get-contexts
kubectl config delete-context <<CONTEXT_NAME>>
```

Step 4.) Log into the Gold and Gold DR clusters via the command line, using the `sso-action-deployer-######-token-` tokens.

Step 5.) Run the `deploy-gold-in-standby.sh` script.  **Warning: This will delete the gold PVCs and patroni configmaps.**
```
./deploy-gold-in-standby.sh <<NAMESPACE>>
```

When this script completes the Patroni-Gold cluster should be in stand-by mode, following the active patroni cluster.


## Scripts

There are five scripts in [transition-scripts](./transition-scripts) to provision a set of Keycloak deployments in Gold & Golddr clusters in different scenarios.
As a common step, please check the version of the Keycloak Helm chart to ensure it is the desired one.

### deploy.sh

It deployes Keycloak resources in the target namespaces in a normal situation and sets "active" mode in Gold cluster and "standby" mode in Golddr cluster.
It upgrades the current Helm deployments if there are existing Helm deployments, otherwise it installs them. **Note: This will deploy both Gold and GoldDR in the same script. This is no longer the deployment pattern the team has decided to use.**

```sh
cd transition-scripts
deploy.sh <namespace>
```

### deploy-by-cluster.sh

This will deploy the Keycloak application in a single cluster in it's active starte.  It is run using the command:

```sh
cd transition-scripts
deploy-by-cluster.sh <namespace> <cluster>
```

### destroy.sh

It destroyes Keycloak resources in the target namespaces in Gold & Golddr.

```sh
cd transition-scripts
destroy.sh <namespace>
```

### switch-to-golddr.sh

It sets the target namespace of the Golddr cluster active, can be automatically trigered by the switchover agent.

```sh
cd transition-scripts
switch-to-golddr.sh <namespace>
```

### set-dr-to-standby.sh

Returns the patroni-dr to standby once keycloak gold is back to it's active mode.  It changes no gold configuration, meaning there will be no service outage.  The `deletePVC` option is 'true' or 'false', if xlogs fail to synch on fail back, it will delete the PVCs in DR as well as the config files.  Ensuring a fresh install.

```sh
cd transition-scripts
set-dr-to-standby.sh <namespace> <deletePVC>
```

### switch-to-dr-set-gold-standby.sh

This will set the GoldDR cluster to active, but also finish by setting patroni-Gold to standby.  This prevents the automatic failback to the gold cluster (GSLB sees gold cluster as down).  This is useful if we expect long term instability in the Gold cluster and wish to direct traffic to GoldDr for a prolonged period of time.

```sh
cd transition-scripts
switch-to-dr-set-gold-standby.sh <namespace>
```

### synch-gold-to-dr-then-set-gold-active.sh

**PATRONI-GOLD is no longer put in standby mode.  The only use for this is if the GoldDR deployment has been active a long time and we do not wish to lose the changes made during the failover.**

The first step of this script sets the patroni-gold stateful set to standby mode, in order to insure it has the latest changes from patroni-golddr. It then sets the patroni-Gold cluster to active, and the corresponding Golddr cluster standby.

This workflow was designed to run in the recovery stage of the Gold cluster's failover. However it has since been deprecated.

```sh
cd transition-scripts
synch-gold-to-dr-then-set-gold-active.sh <namespace>
```
### test-workflow.sh

This action was triggered by the `testworkflows.yml` action. The multi step, logic was needed when patroni-gold had to synch with patroni-dr. However, it will not be nessessary if patroni-gold is no longer put in standby mode.

## Release Process

- Create a pull request from `dev` to `main` and update pull request labels to choose a specific type of release
- `release:major` - will create a major release (example: `v1.0.0` -> `v2.0.0`)
- `release:minor` - will create a minor release (example: `v1.0.0` -> `v1.1.0`)
- `release:patch` - will create a patch release (example: `v1.0.0` -> `v1.0.1`)
- `release:norelease` - will not trigger any release
