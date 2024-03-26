import socket
import asyncio
import logging
import time
import json

from multiprocessing import Queue
from config import config

from urllib.request import urlopen
from urllib.error import *

from datetime import datetime, timedelta
import pytz

logger = logging.getLogger(__name__)

passive_ip = config.get('passive_ip')

sleep_time = 60

time_preemptive_start = config.get("preemptive_failover_start_time")
time_preemptive_end = config.get("preemptive_failover_end_time")

tz = pytz.timezone("America/Vancouver")


def countdown_to_switchover(q: Queue):
    logger.info("starting dns countdown...")
    time_preemptive_start = config.get("preemptive_failover_start_time")
    time_preemptive_end = config.get("preemptive_failover_end_time")
    if time_preemptive_end != "" and time_preemptive_start != "":
        try:
            start_time = tz.localize(datetime.strptime(time_preemptive_start, "%Y/%m/%d %H:%M"))

            end_time = tz.localize(datetime.strptime(time_preemptive_end, "%Y/%m/%d %H:%M"))
            agent_startup_time = datetime.now().astimezone(tz)

        except Exception as e:
            logger.error("Exception while formatting datetime input, expected format: '%Y/%m/%d %H:%M %z'")
            logging.error('Error at %s', 'division', exc_info=e)
            return 'error'

        if agent_startup_time < start_time and start_time < end_time:
            logger.info("Start the countdown to preemptive failover")
            try:
                new_loop = asyncio.new_event_loop()
                asyncio.set_event_loop(new_loop)
                new_loop.create_task(count_down_to_preemptive_action(start_time, end_time, q))
                new_loop.run_forever()
            except Exception as e:
                logger.error("Exception while attempting to run failover countdown loop.")
                logging.error('Error at %s', 'division', exc_info=e)
                return 'error'
        else:
            logger.info("Invalid times entered for start and end of Failover window.")
            return

    else:
        logger.info("No preemptive failover configured")
        return


async def count_down_to_preemptive_action(start_time: datetime, end_time: datetime, q: Queue):
    logger.info("A PREEMPTIVE FAILOVER TO GOLDDR IS SCHEDULED AT %s", start_time)
    logger.info("TRAFFIC WILL BE RETURNED TO GOLD AT: %s", end_time)

    countdown_enabled = True
    preemptive_failover_triggered = False

    while countdown_enabled:

        current_time = datetime.now().astimezone(tz)

        if start_time > current_time:
            time_left = start_time - current_time
            logger.info(f'The preemptive failover will occur in {timedelta(seconds=time_left.seconds)} hh:mm:ss.')
        elif not preemptive_failover_triggered:
            preemptive_failover_triggered = True
            q.put({'event': 'preemptive_failover', 'message': 'The preemptive failover to GoldDR is triggered'})
        elif end_time > current_time:
            time_left = end_time - current_time
            logger.info(f'Traffic returns to gold in: {timedelta(seconds=time_left.seconds)} hh:mm:ss.')
        else:
            # May need to put an additional check in place here for gold health
            countdown_enabled = False
            q.put({'event': 'preemptive_failback', 'message': 'The Gold route is being re-enabled'})

        time.sleep(sleep_time)
