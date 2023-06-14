import sys
import logging
import traceback
import requests
import json

from multiprocessing import Queue
from config import config

logger = logging.getLogger(__name__)


def handle_queues(queue: Queue, processes: list):
    previous_valid_ip = 'undefined'
    valid_ips = [config.get('active_ip'), config.get('passive_ip')]
    while True:
        try:
            item = queue.get()
            logger.info(item)
            if item['event'] == 'dns':
                ip = item['result']
                logger.debug("DNS resolution: %s", ip)

                action_dispatcher(ip, previous_valid_ip, valid_ips[0], valid_ips[1])

                if ip in valid_ips:
                    previous_valid_ip = ip

        except Exception as ex:
            logger.error('Unknown error in logic. %s' % ex)
            traceback.print_exc(file=sys.stdout)


def action_dispatcher(ip: str, prev_ip: str, active_ip: str, passive_ip: str):
    if (ip == active_ip and prev_ip == passive_ip):
        logger.info("active_ip")
        dispatch_rocketchat_webhook("Gold")
        dispatch_css_maintenance_action(False)
    elif (ip == passive_ip and prev_ip == active_ip):
        logger.info("passive_ip")
        dispatch_action()
        dispatch_rocketchat_webhook("GoldDR")
        dispatch_css_maintenance_action(True)
    # elif prev_ip == 'undefined':
    #     # Trigger an internal alert stating the switchover agent restarted, it's
    #     # environment and where the GSLB is pointing
    # elif ip == 'error':
    #     # Trigger an internal alert stating the GSLB is not resolving any IP, it's
    #     # environment and where the GSLB was previously pointing
    # elif ip == prev_ip:
    #     # Trigger an internal alert stating the GSLB service interuption was
    #     # was resolved
    #     # Include the environment, clusted, and explanation of what is going on


def test_funtion():
    return 5


def dispatch_action():
    url = 'https://api.github.com/repos/%s/%s/actions/workflows/%s/dispatches' % (config.get('gh_owner'), config.get('gh_repo'), config.get('gh_workflow_id'))
    data = {'ref': config.get('gh_branch'), 'inputs': {'namespace': config.get('namespace')}}
    bearer = 'token %s' % config.get('gh_token')
    headers = {'Accept': 'application/vnd.github.v3+json', 'Authorization': bearer}
    x = requests.post(url, json=data, headers=headers)
    if x.status_code == 204:
        logger.info('GH API status: %s' % x.status_code)
    else:
        logger.error('GH API error: %s' % x.content)


def dispatch_rocketchat_webhook(cluster: str):
    url = config.get('rc_url')
    bearer = 'token %s' % config.get('rc_token')
    headers = {'Accept': 'application/json', 'Authorization': bearer}

    namespace = config.get('namespace')
    env = namespace[7:]
    if cluster == 'GoldDR':
        message = f"@all **The Gold Keycloak {env} instance has failed over to the DR cluster**\n* After the DR deployment is complete, end users may continue to login to your apps using the Pathfinder SSO Service (standard or custom).\n* Any changes made to a project's config using the Pathfinder SSO Service (standard or custom realm) while the app is in its failover state will be lost when the app is restored to the Primary cluster. (*aka your config changes will be lost*). \n* The priority of this service is to maximize availability to the end users and automation."
    elif cluster == 'Gold':
        message = f"@all **The Gold Keycloak {env} instance has been restored to the Primary cluster (aka back to normal).**\n* We are be back to normal operations of the Pathfinder SSO Service (standard and custom).\n* Changes made to a project's config using the Pathfinder SSO Service (standard or custom realm) during Disaster Recovery will be missing. \n* The priority of this service is to maximize availability to the end users and automation."

    data = {"text": message}

    try:
        x = requests.post(url, json=data, headers=headers)
        if x.status_code == 200:
            logger.info('Rocket chat message sent.')
        else:
            logger.error('Rocket chat API error: %s' % x.content)
    except Exception as ex:
        logger.error('Unknown error in logic. %s' % ex)
        traceback.print_exc(file=sys.stdout)


def dispatch_css_maintenance_action(maintenance_mode: bool):
    if config.get('css_gh_token') == '':
        logger.info('CSS maintenance mode is not configured for this namespace')
    else:
        url = 'https://api.github.com/repos/%s/%s/actions/workflows/%s/dispatches' % (config.get('gh_owner'), config.get('css_repo'), config.get('css_maintenance_workflow_id'))
        data = {'ref': config.get('css_branch'), 'inputs': {'environment': config.get('css_environment'), 'maintenanceEnabled': maintenance_mode}}
        bearer = 'token %s' % config.get('css_gh_token')
        headers = {'Accept': 'application/vnd.github.v3+json', 'Authorization': bearer}
        x = requests.post(url, json=data, headers=headers)
        if x.status_code == 204:
            logger.info('CSS GH API status: %s' % x.status_code)
        else:
            logger.error('GH API error: %s' % x.content)
