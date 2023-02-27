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
    gold_port=os.environ.get("GOLD_PORT", 'xxxxx'),
    gold_patroni_service=os.environ.get("GOLD_PATRONI_SERVICE_NAME", 'sso-patroni-config-readonly-gold'),
    dr_patroni_service=os.environ.get("DR_PATRONI_SERVICE_NAME", 'sso-patroni-config-readonly')
)
