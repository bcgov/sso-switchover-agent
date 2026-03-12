from config import config
from github import GithubIntegration, Auth  # type: ignore
import base64
import logging
import requests


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


def dispatch_action_by_id(workflow_id: str):
    try:
        logger.info('The gh_owner is: %s' % config.get('gh_owner'))
        logger.info('The gh_repo is: %s' % config.get('gh_repo'))
        logger.info('The workflow id is: %s' % workflow_id)
        url = 'https://api.github.com/repos/%s/%s/actions/workflows/%s/dispatches' % (config.get('gh_owner'), config.get('gh_repo'), workflow_id)
        data = {'ref': config.get('gh_branch'), 'inputs': {}}
        bearer = 'Bearer %s' % get_github_access_token()
        headers = {'Accept': 'application/vnd.github.v3+json', 'Authorization': bearer}
        x = requests.post(url, json=data, headers=headers)
        if x.status_code == 204:
            logger.info('GH API status: %s' % x.status_code)
        else:
            logger.error('GH API error: %s' % x.content)
    except Exception as ex:
        logger.error('The dispatch action failed. %s' % ex)


if __name__ == "__main__":
    dispatch_action_by_id("xlog-cron-compare.yml")
