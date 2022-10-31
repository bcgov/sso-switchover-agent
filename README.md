# sso-switchover-agent

Switchover Agent in the Disaster Recovery Scenario between Gold &amp; Golddr. The workflow is heavily inspired by `API Gateway Team`'s [Switchover Agent](https://github.com/bcgov/switchover-agent).

## Using switchover agent as a deployment tool.

In adition to the disaster recovery (switchover) agent, the keycloak deployment in gold is managed through the scripts in this repo. These scripts can be triggered from a local dev environment, the action in the github repo, or automatically via the switchover agent.

### Triggering the deployments/transitions locally

The local deployment workflow is an option if keycloak needs to be redeployed and github actions are down.  It is also a useful workflow when making changes ot the helm charts.   Deploying changes directly to the sandbox environment is easier and less time intensive than requiring a code review and merging a PR. See [Local dev environment set up](#local-development-environment) and [Scripts](#scripts) documentation.

### Triggering the deployments/transisiont in github

The github actions found [here](.github/workflows) can be triggered manually in the repo.  The actions allow a user to deploy the resources in gold and gold dr, set dr to active, and set gold to active.  These require and target namespace and deployment branch as inputs.


## The switchover agent

The switchover agent monitor is deployed in the Gold DR namespace for a given project and watched the global services load balancer to see if the DNS has been redirected to the Gold DR url.  If it detects the change it will automatically trigger the failover to the DR cluster.

<!--   TODO: DOCUMENT THE AGENT DEPLOYMENT AND FAILOVER HISTORY -->
 - how do we deploy the agent itself
 - where is the history of failovers stored?



## Local development environment

As with most sso team repos the switchover agent uses the asdf tool for local package management.  The sso-keycloak [Developer Guidelines](https://github.com/bcgov/sso-keycloak/blob/dev/docs/developer-guide.md) provide the steps needed to set up and install the local tools.

For the switchover scripts to work the user must provide credentials for both gold and gold-dr.  Using the terminal they can login using:

```
oc login --token=<<gold service account deployer token>> --server=https://api.gold.devops.gov.bc.ca:6443
oc login --token=<<golddr service account deployer token>> --server=https://api.golddr.devops.gov.bc.ca:6443
```

The tokens for deploying will be the service account deployer tokens.

## Disaster recovery workflow

### When gold goes down

When and outage occurs, and the switchover agent is on, the `switch-to-golddr.sh` script will trigger.  Setting gold-dr database to be the leader and spinning up the keycloak-dr instance.  It will take about 10 to 15 minutes for keycloak to be back up and running. It will also attempt to put patroni-gold into standby mode, traking any changes that occur in patroni-gold-dr.

If this script does not trigger you will have to do it manually either through actions or your local dev environment. Whether you trigger the scripts locally or through actions, the workflow is the same. The action is `Set the dr deployment to active`, the script is documented [bellow](#switch-to-golddr.sh).

### When gold is restored

When the Gold cluster is back in a healthy state, you will need to manually trigger the switchover from Gold DR to Gold.  This process is not automated by the switchover agen because it will cause a 10 to 15 minute outage for users and it may be best to delay the restoration until a low traffic time of day.

Before triggering the restore, make certain gold patroni is in standby mode, following the gold dr patroni cluster.  Once done, trigger the github action `Set the gold deployment to active`, or, if Github actions are down, run the script `switch-to-gold.sh` in your local dev environment.

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
