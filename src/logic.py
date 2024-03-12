import sys
import logging
import traceback
import requests
import json
from clients.dns import check_dns_by_env

from multiprocessing import Queue
from config import config

logger = logging.getLogger(__name__)


css_repo = config.get('css_repo')
css_branch = config.get('css_branch')
css_environment = config.get('css_environment')
css_maintenance_workflow_id = config.get('css_maintenance_workflow_id')
css_gh_token = config.get('css_gh_token')


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

            elif item['event'] == 'maintenance':
                dr_maintenance_mode = item['maintenance_mode']
                dispatch_rocketchat_webhook(dr_maintenance_mode)
                logger.debug("The maintenance mode changed")

            elif item['event'] == 'team_rocketchat':
                alert_team_to_switch(item['delay'])
                logger.debug(item['message'])

            elif item['event'] == 'preemptive_failover':
                dispatch_action_by_id(config.get("preemptive_failover_workflow_id"))
                logger.debug(item['message'])

            elif item['event'] == 'preemptive_failback':
                dispatch_action_by_id(config.get("enable_gold_route_workflow_id"))
                logger.debug(item['message'])

        except Exception as ex:
            logger.error('Unknown error in logic. %s' % ex)
            traceback.print_exc(file=sys.stdout)


def action_dispatcher(ip: str, prev_ip: str, active_ip: str, passive_ip: str):
    if (ip == active_ip and prev_ip == passive_ip):
        css_maintenance_to_active = True
        for env in ['dev', 'test', 'prod']:
            dns_matched = check_dns_by_env(env, passive_ip)
            if (dns_matched or dns_matched == 'error'):
                logger.info("%s is still pointing to %s or unable to check dns" % (env, passive_ip))
                css_maintenance_to_active = False
                break

        if css_maintenance_to_active:
            logger.info("active_ip")
            dispatch_css_maintenance_action(False)
        else:
            logger.info("Failed to turn off the css maintenance mode")
    elif (ip == passive_ip and prev_ip == active_ip):
        logger.info("passive_ip")
        dispatch_action_by_id(config.get('gh_workflow_id'))
        dispatch_css_maintenance_action(True)


# This runs a github action in the sso-switchover agent repos currently works with actions with 3 three required inputs
# gh_branch (usually dev or main)
# project (SANDBOX or PRODUCTION)
# environment (dev, test, prod)
def dispatch_action_by_id(workflow_id: str):
    environment = config.get('namespace')[7:]
    url = 'https://api.github.com/repos/%s/%s/actions/workflows/%s/dispatches' % (config.get('gh_owner'), config.get('gh_repo'), workflow_id)
    data = {'ref': config.get('gh_branch'), 'inputs': {'project': config.get('project'), 'environment': environment}}
    bearer = 'token %s' % config.get('gh_token')
    headers = {'Accept': 'application/vnd.github.v3+json', 'Authorization': bearer}
    x = requests.post(url, json=data, headers=headers)
    if x.status_code == 204:
        logger.info('GH API status: %s' % x.status_code)
    else:
        logger.error('GH API error: %s' % x.content)


def dispatch_rocketchat_webhook(maintenance_mode: str):
    url = config.get('rc_url')
    bearer = 'token %s' % config.get('rc_token')
    headers = {'Accept': 'application/json', 'Authorization': bearer}

    namespace = config.get('namespace')
    env = namespace[7:]

    if namespace.startswith("c6af30") or namespace.startswith("e4ca1d"):
        css_url = "https://bcgov.github.io/sso-requests-sandbox"
    else:
        css_url = "https://bcgov.github.io/sso-requests"

    if maintenance_mode == 'maintenance_up':
        message = """@all **The Gold Keycloak %s instance is in the process of \
            failing over to the DR cluster** \n* The \
            [CSS App](%s) is being put in Maintenance mode. Please check our \
            [Uptime](https://uptime.com/statuspage/bcgov-sso-gold) \
            before using our service.""" % (env, css_url)
    elif maintenance_mode == 'keycloak_up':
        message = """@all **The Gold Keycloak %s instance has failed over to the DR \
            cluster** \n* DR deployment is complete, end users continue to login to your \
            apps using the Pathfinder SSO Service (standard or custom). \n* Any changes \
            made to a project's config using the Pathfinder SSO Service (standard or \
            custom realm) while the app is in its failover state will be lost when the \
            app is restored to the Primary cluster. (aka your config changes will be \
            lost). \n* The priority of this service is to maximize availability to the \
            end users and automation.""" % (env)
    elif maintenance_mode == 'gold_up':
        message = """@all **The Gold Keycloak %s instance has been restored to the Primary \
            cluster (aka back to normal).** \n* We are be back to normal operations of \
            the Pathfinder SSO Service (standard and custom).\n* Changes made to a \
            project's config using the Pathfinder SSO Service (standard or custom realm) \
            during Disaster Recovery will be missing. \n* The priority of this service is \
            to maximize availability to the end users and automation.""" % (env)

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


def alert_team_to_switch(delay):
    try:
        url = config.get('rc_url_sso_ops')
        namespace = config.get('namespace')
        bearer = 'token %s' % config.get('rc_token_sso_ops')
        headers = {'Accept': 'application/json', 'Authorization': bearer}
        message = """@here **The GSLB has changed the DNS it is pointing to for the %s namespace. \
            if this persists longer than %s seconds the switchover process may \
            be triggered.""" % (namespace, delay)
        data = {"text": message}
        x = requests.post(url, json=data, headers=headers, timeout=10)
        if x.status_code == 200:
            logger.info('Rocket chat message sent.')
        else:
            logger.error('Rocket chat API error: %s' % x.content)

    except Exception as ex:
        logger.error('Unknown error in logic. %s' % ex)


def dispatch_css_maintenance_action(maintenance_mode: bool):

    if css_repo == '' or css_branch == '' or css_environment == '' or css_maintenance_workflow_id == '' or css_gh_token == '':
        logger.info('CSS maintenance mode is not configured for this namespace')
    else:
        url = 'https://api.github.com/repos/%s/%s/actions/workflows/%s/dispatches' % (config.get('gh_owner'), css_repo, css_maintenance_workflow_id)
        data = {'ref': css_branch, 'inputs': {'environment': css_environment, 'maintenanceEnabled': maintenance_mode}}
        bearer = 'token %s' % css_gh_token
        headers = {'Accept': 'application/vnd.github.v3+json', 'Authorization': bearer}
        try:
            logger.info(f'Deploying CSS app in maintenance_mode={maintenance_mode}')
            x = requests.post(url, json=data, headers=headers)
        except Exception as ex:
            logger.error('Maintenance mode action not triggered. Unknown error in logic. %s' % ex)

        if x.status_code == 204:
            logger.info('CSS GH API status: %s' % x.status_code)
        else:
            logger.error('GH API error: %s' % x.content)
