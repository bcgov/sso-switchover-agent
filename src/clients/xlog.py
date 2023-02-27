import socket
import asyncio
import logging
import time

import json
import requests

from config import config
from datetime import datetime
from multiprocessing import Queue

logger = logging.getLogger(__name__)


def xlog_watch(domain_name: str, q: Queue):
    logger.info("starting xlog comparison...")

    new_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(new_loop)
    new_loop.create_task(xlog_lookup(domain_name, q))
    new_loop.run_forever()

# Comapare the xlogs between patroni-gold and patroni-dr
# if they are still in synch forward that time to the logic
# method.


async def xlog_lookup(service_name: str, q: Queue):
    gold_service = config.get('gold_patroni_service')
    dr_service = config.get('dr_patroni_service')
    namespace = config.get('namespace')
    gold_port = config.get('gold_port')
    try:
        if gold_port == "xxxxx":
            raise Exception("The gold port is not configured, please add GOLD_PORT to the switchover config secret.")
    except Exception as e:
        logger.error(e)

    gold_url = f"http://{gold_service}.{namespace}.svc.cluster.local:{gold_port}/patroni"
    dr_url = f"http://{dr_service}.{namespace}.svc.cluster.local:8008/patroni"
    while True:
        last_synch_time = None
        try:
            patroni_dr_response = requests.get(dr_url, timeout=5)
            patroni_dr_config = json.loads(patroni_dr_response.text)
            patroni_dr_xlog = patroni_dr_config['xlog']['received_location']

            patroni_gold_response = requests.get(gold_url, timeout=5)
            patroni_gold_config = json.loads(patroni_gold_response.text)
            if patroni_gold_config['role'] == 'replica':
                patroni_gold_xlog = patroni_gold_config['xlog']['received_location']
            else:
                patroni_gold_xlog = patroni_gold_config['xlog']['location']

            if patroni_gold_xlog != patroni_dr_xlog:
                logger.info(f"The xlogs are out of synch")
            else:
                logger.info("The xlogs are synched")
                last_synch_time = datetime.now()

        except requests.exceptions.RequestException as e:
            logger.error("XLOG failed response")
            logger.error(e)

        except KeyError as kee:
            logger.error("Xlog not found in response")
            logger.error(kee)
            logger.error(f"The gold config is: {patroni_gold_config}")
            logger.error(f"The dr config is: {patroni_dr_config}")

        if last_synch_time is not None:
            q.put({'event': 'xlog', 'time_synch': last_synch_time,
                  'message': 'The xlogs are synched'})
            last_synch_time = None
        time.sleep(60)
