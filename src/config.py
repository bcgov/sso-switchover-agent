import os

config = dict(
    port=os.environ.get("PORT", "8080"),
    domain_name=os.environ.get("DOMAIN_NAME", 'localhost'),
    active_ip=os.environ.get("ACTIVE_IP", '142.34.229.4'),
    passive_ip=os.environ.get("PASSIVE_IP", '142.34.64.4'),
    python_env=os.environ.get("PYTHON_ENV", 'production'),
    gh_owner=os.environ.get("GH_OWNER", 'bcgov'),
    gh_repo=os.environ.get("GH_REPO", 'sso-switchover-agent'),
    gh_branch=os.environ.get("GH_BRANCH", 'main'),
    gh_workflow_id=os.environ.get("GH_WORKFLOW_ID", 'switch-to-golddr.yml'),
    gh_token=os.environ.get("GH_TOKEN", ''),
    namespace=os.environ.get("NAMESPACE", 'xxxxxx-dev'),
    project=os.environ.get("PROJECT", ''),
    rc_url=os.environ.get("RC_URL", ''),
    rc_token=os.environ.get("RC_TOKEN", ''),
    rc_url_sso_ops=os.environ.get("RC_URL_SSO_OPS", ''),
    rc_token_sso_ops=os.environ.get("RC_TOKEN_SSO_OPS", ''),
    css_repo=os.environ.get("CSS_REPO", ''),
    css_branch=os.environ.get("CSS_BRANCH", ''),
    css_environment=os.environ.get("CSS_ENVIRONMENT", ''),
    css_maintenance_workflow_id=os.environ.get("CSS_MAINTENANCE_WORKFLOW_ID", ''),
    css_gh_token=os.environ.get("CSS_GH_TOKEN", ''),
    delay_switchover_by_secs=os.environ.get("DELAY_SWITCHOVER_BY_SECS", 0),
    preemptive_failover_start_time=os.environ.get("PREEMPTIVE_FAILOVER_START_TIME", ""),
    preemptive_failover_end_time=os.environ.get("PREEMPTIVE_FAILOVER_END_TIME", ""),
    preemptive_failover_workflow_id=os.environ.get("PREEMPTIVE_WORKFLOW_ID", "preemptive-failover.yml"),
    enable_gold_route_workflow_id=os.environ.get("ENABLE_GOLD_ROUTE_WORKFLOW_ID", "turn-off-gold-routing.yml"),
    uptime_status_api="https://uptime.com/api/v1/statuspages/",
    uptime_status_page_id=os.environ.get("UPTIME_STATUS_PAGE_ID", ""),
    uptime_status_token=os.environ.get("UPTIME_STATUS_TOKEN", ""),
    ches_api_endpoint="https://ches.api.gov.bc.ca/api/v1/email",
    ches_token_endpoint=os.environ.get("CHES_TOKEN_ENDPOINT", ""),
    ches_username=os.environ.get("CHES_USERNAME", ""),
    ches_password=os.environ.get("CHES_PASSWORD", ""),
    log_email=os.environ.get("LOG_EMAIL", ""),
    gh_app_id=os.environ.get("GH_APP_ID", ""),
    gh_installation_id=os.environ.get("GH_INSTALLATION_ID", ""),
    gh_app_private_key=os.getenv("GH_APP_PRIVATE_KEY", "")
)
