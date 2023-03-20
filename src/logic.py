import sys
import logging
import traceback
import requests

from multiprocessing import Queue
from config import config

logger = logging.getLogger(__name__)


def handle_queues(queue: Queue, processes: list):
    while True:
        try:
            item = queue.get()
            logger.info(item)

            if item['event'] == 'dns':
                ip = item['result']
                logger.debug("DNS resolution: %s", ip)
                if ip == config.get('active_ip'):
                    logger.info("active_ip")
                elif ip == config.get('passive_ip'):
                    logger.info("passive_ip")
                    dispatch_action()

        except Exception as ex:
            logger.error('Unknown error in logic. %s' % ex)
            traceback.print_exc(file=sys.stdout)


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
