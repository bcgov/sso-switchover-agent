# sso-switchover-agent

Switchover Agent in the Disaster Recovery Scenario between Gold &amp; Golddr. The workflow is heavily inspired by `API Gateway Team`'s [Switchover Agent](https://github.com/bcgov/switchover-agent).

## Using switchover agent as a deployment tool.

In addition to the disaster recovery (switchover) agent, the keycloak deployment in gold is managed through the scripts in this repo. These scripts can be triggered from a local dev environment, the action in the github repo, or automatically via the switchover agent.

The Keycloak deployments in Gold and Gold DR are manage by helm, in the `transition-scripts/` directory.  This is where you will find the deployment values.  The helm chart version is set by `KEYCLOAK_HELM_CHART_VERSION` variable in the `transition-scripts/helpers/helm.sh` file.  It will need to be updated for the actions to deploy a new version of the helm chart.

### Triggering the deployments/transitions locally

The local deployment workflow is an option if keycloak needs to be redeployed and github actions are down.  It is also a useful workflow when making changes to the helm charts.   Deploying changes directly to the sandbox environment is easier and less time intensive than requiring a code review and merging a PR. See [Local dev environment set up](#local-development-environment) and [Scripts](#scripts) documentation.

**Developer Note**: When deploying client facing apps from a local environment it is crucial to have the branch up to date with remote the `dev`.  If the image tag in `/transition-scripts/values/values.yaml` does not match the image tag on the remote dev branch, the keycloak image will revert the next time the github action is triggered.

### Triggering the deployments/transisions in github

The github actions found [here](.github/workflows) can be triggered manually in the repo.  The actions allow a user to deploy the resources in gold and gold dr, set dr to active, and set gold to active.  These require and target namespace and deployment branch as inputs.


## The switchover agent

The switchover agent is deployed in the Gold DR namespace for a given project and watches changes in the DNS record.  If it detects the change it will automatically trigger the failover to the DR cluster.

The switchover agent app is built and deployed automatically on pr merges to `dev` and `main` using the action `publish-image.yml`.  On merging to the `dev` branch, the app is deployed to the Gold DR sandbox `dev` namespace.  On merging to the `main` branch, the app is built and deployed to the Gold DR production `dev`, `test`, and `prod` namespaces.

The history of times the switchover agent has been triggered can be seen by looking at the history of the `Set the dr deployment to active` action in this repo.

### DNS rerouting

The DNS rerouting is handled by the a golobal server load balancer (GSLB) that monitors the keycloak health endpoint `https://loginproxy.gov.bc.ca/auth/realms/master/.well-known/openid-configuration` and, if it is not accessible, the GSLB will redirect traffic to the Gold DR cluster app.

The Switchover agent monitors the keycloak app url (loginproxy.gov.bc.ca for production) and checks  every 5 seconds if the DNS record has changed. If it has, that indicates GSLB is redirecting to DR and the 'switch to dr' github action is triggered.


## Local development environment

As with most sso team repos the switchover agent uses the asdf tool for local package management.  The sso-keycloak [Developer Guidelines](https://github.com/bcgov/sso-keycloak/blob/dev/docs/developer-guide.md) provide the steps needed to set up and install the local tools.

For the switchover scripts to work the user must provide credentials for both gold and gold-dr.  Using the terminal they can login using:

```
oc login --token=<<gold oc-sso-deployer-token>> --server=https://api.gold.devops.gov.bc.ca:6443
oc login --token=<<golddr oc-sso-deployer-token>> --server=https://api.golddr.devops.gov.bc.ca:6443
```

The tokens for deploying will be the service account deployer tokens. Note: the scripts will not run if is is not the `oc-sso-deployer-token`.  There are many `deployer-token` secrets, only one `oc-sso-deployer-token`.

## Disaster recovery workflow

### When gold goes down

When and outage occurs, and the switchover agent is on, the `switch-to-golddr.sh` script will trigger.  Setting gold-dr database to be the leader and spinning up the keycloak-dr instance.  It will take about 10 to 15 minutes for keycloak to be back up and running. It will also attempt to put patroni-gold into standby mode, traking any changes that occur in patroni-gold-dr.

If patroni-gold is down, or the Gold cluster cannot be reached, it will not be put in standby mode.  The github action will look like it failed, however keaycloak and patroni will have been successfully deployed in the Gold DR cluster.

If this script does not trigger you will have to do it manually either through github actions or your local development environment. Whether you trigger the scripts locally or through actions, the workflow is the same. The action is `Set the dr deployment to active`, the script is documented [below](#switch-to-golddr.sh).

### When gold is restored

When the Gold cluster is back in a healthy state, you will need to manually trigger the switchover from Gold DR to Gold.  This process is not automated by the switchover agent because it will cause a 10 to 15 minute outage for users and it may be best to delay the restoration until a low traffic time of day.

Before triggering the restoration of Keycloak in Gold.  Confirm the Gold DR cluster is healthy and working as expected. If it's not in a healthy state, it may better restore Gold database from the daily backup and accept losing a day's data.

When ready to restore gold, trigger the github action `Set the gold deployment to active`, or, if Github actions are down, run the script `switch-to-gold.sh` in your local dev environment.

#### State conflict

Even if patroni-gold is not in standby mode, the `switch-to-gold.sh`script is designed to handle that case.  It will put gold into standby mode to get the latest changes, then switch gold to the active cluster.   If this fails it may be necessary to delete the gold patroni deployment and recreate it in standby mode following the patroni-dr cluster.

<!-- MORE DOCUMENTATION TO BE ADDED HERE WHEN THE WORKFLOW SCRIPT IS CREATED -->


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
