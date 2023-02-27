import sys
import logging
import traceback
import requests

from multiprocessing import Queue
from config import config
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


def handle_queues(queue: Queue, processes: list):
    time_last_synch = None
    while True:
        try:
            item = queue.get()
            logger.info(item)
            if item['event'] == 'xlog':
                logger.info(f"The xlogs were in synch at {item['time_synch']}")
                time_last_synch = item['time_synch']

            if item['event'] == 'dns':
                ip = item['result']
                logger.debug("DNS resolution: %s", ip)
                if ip == config.get('active_ip'):
                    logger.info("active_ip")
                elif ip == config.get('passive_ip'):
                    logger.info("passive_ip")
                    current_time = datetime.now()
                    if (time_last_synch is None or (current_time - timedelta(minutes=15) > time_last_synch)):
                        logger.info("XLogs have not been in synch for over 15 minutes, automatic failover to gold dr blocked")
                    else:
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
