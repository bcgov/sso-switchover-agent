from config import config
from github import GithubIntegration, Auth
import os
import base64


def get_github_access_token() -> str:
    """
    Create a GitHub App installation access token using the GitHub API.

    This function creates an installation access token for a GitHub App. It uses the
    GitHub API to authenticate and create the token.

    Returns:
        str: The installation access token.
    """
    private_key = base64.b64decode(config.get('gh_app_private_key')).decode("utf-8")

    try:
        auth = Auth.AppAuth(config.get('gh_app_id'), private_key)
        gi = GithubIntegration(auth=auth)
        return gi.get_access_token(
            installation_id=config.get('gh_installation_id')
        ).token

    except Exception as e:
        raise RuntimeError(f"Error creating installation access token: {str(e)}")
