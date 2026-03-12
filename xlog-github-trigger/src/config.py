import os

config = dict(
    gh_owner=os.environ.get("GH_OWNER", 'bcgov'),
    gh_branch=os.environ.get("GH_BRANCH", 'dev'),
    gh_repo=os.environ.get("GH_REPO", 'sso-switchover-agent'),
    gh_app_id=os.environ.get("GH_APP_ID", ""),
    gh_installation_id=os.environ.get("GH_INSTALLATION_ID", ""),
    gh_app_private_key=os.getenv("GH_APP_PRIVATE_KEY", "")
)
