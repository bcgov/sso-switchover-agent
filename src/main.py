import os
import sys
import logging
from multiprocessing import Process, Queue

from clients.dns import dns_watch
from logic import handle_queues
from logic_test import test_queues, set_active_hosts
from config import config

# from settings import app_env, app_url
from api import fastapi

logging.basicConfig(
    stream=sys.stdout,
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)-5s] %(name)-20s %(message)s')

logger = logging.getLogger(__name__)

if __name__ == '__main__':
    test_mode = config.get('python_env') == 'test'

    fastapi_proc = Process(target=fastapi)
    fastapi_proc.start()

    processes = []
    queue = Queue()

    t = Process(target=dns_watch, args=(
        config.get('domain_name'),
        queue
    ))
    processes.append(t)

    logic_handler = test_queues if test_mode else handle_queues
    t = Process(target=logic_handler, args=(queue, processes))
    processes.append(t)

    if test_mode:
        set_active_hosts()

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
    logger.info("All terminated.")

    if test_mode and queue.qsize() > 0:
        sys.exit(1)
        # sys.exit(1 if queue.get() == 'failure' else 0)

    sys.exit(0)
