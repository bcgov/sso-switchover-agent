# Configuring the switchover agent

There are multiple environment variables set in the secret `sso-switchover-agent`.  Some of these variables are necessary for the app to trigger the switchover properly, others are only needed for notifications being sent out.

## Necessary varibles.

 - DOMAIN_NAME: The url the switchover agent monitors.  e.g. `dev.sandbox.loginproxy.gov.bc.ca`
 - GH_BRANCH: The branch in the sso-switchover-agent repo from which to deploy. `dev` for sandbox environments `main` for production.
 - GH_TOKEN: The personal access token for deploying the switchover actions.
 - NAMESPACE: The namespace in which we will we be deploying. In general, it is the same namespace as the switchover agent deployment.
 - PROJECT: The project (PRODUCTION, SANDBOX, OLD-SANDBOX), which we will be deploying.

## Delay failover

There is an optional delay feature on the switchover agent that prevents the agent from triggering if the GSLB briefly sends traffic away from gold for a few seconds.

`DELAY_SWITCHOVER_BY_SECS`

Is the time in seconds this delay will last.

## Rocket Chat Integration
To notify rocket chat when failover and failback occurs.  Create a rocket chat webhook (already done for SSO-keyacloak). Then add the following values to the secret file.  Currently the production alerts are client facing (sso), and the sandbox alerts are intertal (sso-ops channel).

 - RC_URL
 - RC_TOKEN
 - RC_URL_SSO_OPS
 - RC_TOKEN_SSO_OPS

 The `*_SSO_OPPS` environment variables are used to notify the team if the switchover agent detected a DNS change without triggering a failover.

## CSS App Integration

The CSS app should be put in maintenance mode when the production environent is down. Leave these blank for all agents except sandbox-dev and production-prod.

 - CSS_REPO: `sso-requests`
 - CSS_MAINTENANCE_WORKFLOW_ID: `deploy-gh-pages-maintenance.yml`
 - CSS_ENVIRONMENT: `dev` for sandbox dev, `prod` for production prod.
 - CSS_GH_TOKEN:  The personal access token for deploying the CSS app.
 - CSS_BRANCH: `dev` for sandbox-dev agent, `main` for production-prod agent.
