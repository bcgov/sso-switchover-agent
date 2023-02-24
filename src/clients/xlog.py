import socket
import asyncio
import logging
import time

import json
import requests

from datetime import datetime
from multiprocessing import Queue

logger = logging.getLogger(__name__)


def xlog_watch(domain_name: str, q: Queue):
    logger.info("starting xlog comparison...")

    new_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(new_loop)
    new_loop.create_task(xlog_lookup(domain_name, q))
    new_loop.run_forever()


async def xlog_lookup(service_name: str, q: Queue):
    last_result = 0
    xlog_outofsynch_counter = 0
    while True:
        last_synch_time = None
        try:
            patroni_dr_response = requests.get('http://sso-patroni-http.c6af30-test.svc.cluster.local:8008/patroni')
            patroni_dr_config = json.loads(patroni_dr_response.text)
            patroni_dr_xlog = patroni_dr_config['xlog']['received_location']
            logger.info(f"The patroni dr xlog is: {patroni_dr_xlog}")

            patroni_gold_response = requests.get('http://sso-patroni-config-gold.c6af30-test.svc.cluster.local:63205/patroni')
            patroni_gold_config = json.loads(patroni_gold_response.text)
            patroni_gold_xlog = patroni_gold_config['xlog']['location']
            logger.info(f"The gold xlog is: {patroni_gold_xlog}")

            if patroni_gold_xlog != patroni_dr_xlog:
                xlog_outofsynch_counter += 1
                logger.info(f"The xlogs have been out of synch for {xlog_outofsynch_counter*5} seconds")

            else:
                # If the xlogs are synched, set the
                xlog_outofsynch_counter = 0
                logger.info("The xlogs are synched")
                last_synch_time = datetime.now()

            result = xlog_outofsynch_counter

        except socket.gaierror:
            logger.error("XLOG failed response")
            # result = 'error'

        if result != "none" and last_result != result:
            q.put({'event': 'dns', 'result': result,
                  'message': 'IP CHANGE %s' % result})
            last_result = result
        time.sleep(5)
