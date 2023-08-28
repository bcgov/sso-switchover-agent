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
    css_repo=os.environ.get("CSS_REPO", ''),
    css_branch=os.environ.get("CSS_BRANCH", ''),
    css_environment=os.environ.get("CSS_ENVIRONMENT", ''),
    css_maintenance_workflow_id=os.environ.get("CSS_MAINTENANCE_WORKFLOW_ID", ''),
    css_gh_token=os.environ.get("CSS_GH_TOKEN", ''),
    delay_switchover_by_secs=os.environ.get("DELAY_SWITCHOVER_BY_SECS", 0),
)
