from config import config
from github import GithubIntegration, Auth  # type: ignore
import base64
import logging

logger = logging.getLogger(__name__)


def get_github_access_token() -> str:
    """
    Create a GitHub App installation access token using the GitHub API.

    This function creates an installation access token for a GitHub App. It uses the
    GitHub API to authenticate and create the token.

    Returns:
        str: The installation access token.
    """

    try:
        private_key = base64.b64decode(config.get('gh_app_private_key')).decode("utf-8")
        auth = Auth.AppAuth(config.get('gh_app_id'), private_key)
        gi = GithubIntegration(auth=auth)
        return gi.get_access_token(
            installation_id=config.get('gh_installation_id')
        ).token
    except (base64.binascii.Error, UnicodeDecodeError) as e:
        logger.error(f"Error decoding github app private key: {str(e)}")
        return None

    except Exception as e:
        logger.error(f"Error creating github installation access token: {str(e)}")
        return None
