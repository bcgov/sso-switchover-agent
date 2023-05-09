# Configuring the switchover agent

There multiple environment variables set in the secret `sso-switchover-agent`.  Some of these variables are necessary for the app to trigger the switchover properly, others are only needed for notifications being sent out.

## Necessary varibles.

 - DOMAIN_NAME: The url the switchover agent monitors.  e.g. `dev.sandbox.loginproxy.gov.bc.ca`
 - GH_BRANCH: The branch in the sso-switchover-agent repo from which to deploy. `dev` for sandbox environments `main` for production.
 - GH_TOKEN: The personal access token for deploying the switchover actions.
 - NAMESPACE: The namespace in which we will we be deploying in. In general the same namespace the switchover agent is hosted in.

## Rocket Chat Integration
To notify rocket chat when failover and failback occurs.  Create a rocket chat webhook (already done for SSO-keyacloak). Then add the following values to the secret file.

 - RC_URL
 - RC_TOKEN

## CSS App Integration

The CSS app should be put in maintenance mode when the production environent is down. Leave these blank for all agents except sandbox-dev and production-prod.

 - CSS_REPO: `sso-requests`
 - CSS_MAINTENANCE_WORKFLOW_ID: `deploy-gh-pages-maintenance.yml`
 - CSS_ENVIRONMENT: `dev` for sandbox dev, `prod` for production prod.
 - CSS_GH_TOKEN:  The personal access token for deploying the CSS app.
 - CSS_BRANCH: `dev` for sandbox-dev agent, `main` for production-prod agent.
