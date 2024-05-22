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

## Uptime.com Status Page Integration

The switchover agent is able to create and close incidents on uptime status pages.  (Production is located at [https://status.loginproxy.gov.bc.ca/](https://status.loginproxy.gov.bc.ca/)).  To do this, two environment vars must be configured:

- UPTIME_STATUS_PAGE_ID: This integer can be found in the status page's non-vanity url for the statu page hosted by uptime.com.
- UPTIME_STATUS_TOKEN: The credential used for the uptime.com API.  It can be found [here](https://uptime.com/api/tokens).
## Preemptive Failover

There are 4 optional environment variables if you need to schedule a failover/failback over night.  These are:
```
PREEMPTIVE_FAILOVER_START_TIME = "YYYY/MM/DD HH:MM"
PREEMPTIVE_FAILOVER_END_TIME = "YYYY/MM/DD HH:MM"
PREEMPTIVE_WORKFLOW_ID = "preemptive-failover.yml
ENABLE_GOLD_ROUTE_WORKFLOW_ID = "turn-off-gold-routing.yml"
```

The time zone is hardcoded to "American/Vancouver".  If you add a couple of valid times to the `PREEMPTIVE_FAILOVER_START_TIME` and `PREEMPTIVE_FAILOVER_END_TIME` and restart the switchover agent, the logs will show the following text:

```
clients.preemptive_count_down A PREEMPTIVE FAILOVER TO GOLDDR IS SCHEDULED AT 2024-03-12 08:38:00-07:00
clients.preemptive_count_down TRAFFIC WILL BE RETURNED TO GOLD AT: 2024-03-12 08:41:00-07:00
```

Then every minute a log will be output describing the state of the failover counter. There are 4 possible messages depending on the countdowns state.

```
[INFO ] clients.preemptive_count_down The preemptive failover will occur in 0:01:53 hh:mm:ss.
[DEBUG] logic                The preemptive failover to GoldDR is triggered
[INFO ] clients.preemptive_count_down Traffic returns to gold in: 0:01:53 hh:mm:ss.
[DEBUG] logic                The Gold route is being re-enabled
```

Pairing this with a couple of DNS checking Uptime alerts will give the team the confidence to schedule a preemptive failover for the loginproxy app.
