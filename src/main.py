import os
import sys
import logging
from multiprocessing import Process, Queue

from clients.dns import dns_watch
from logic import handle_queues
from config import config

# from settings import app_env, app_url
from api import fastapi

logging.basicConfig(
    stream=sys.stdout,
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)-5s] %(name)-20s %(message)s')

logger = logging.getLogger(__name__)

if __name__ == '__main__':

    fastapi_proc = Process(target=fastapi)
    fastapi_proc.start()

    processes = []
    queue = Queue()

    t = Process(target=dns_watch, args=(
        config.get('domain_name'),
        queue
    ))
    processes.append(t)

    t = Process(target=handle_queues, args=(queue,))
    processes.append(t)

    try:
        for process in processes:
            process.start()
        for process in processes:
            process.join()
    except KeyboardInterrupt:
        logger.error("Keyboard Exit")
    except BaseException:
        logger.error("Unknown error.  Exiting")

    for process in processes:
        process.terminate()

    fastapi_proc.terminate()

    logger.error("All terminated.")
