import socket
import asyncio
import logging
import time

from multiprocessing import Queue
from config import config

from urllib.request import urlopen
from urllib.error import *

logger = logging.getLogger(__name__)

passive_ip = config.get('passive_ip')


def dns_watch(domain_name: str, q: Queue):
    logger.info("starting...")

    new_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(new_loop)
    new_loop.create_task(dns_lookup(domain_name, q))
    new_loop.run_forever()


async def dns_lookup(domain_name: str, q: Queue):
    logger.info("DNS Inspection %s" % domain_name)
    last_result = "unknown"
    while True:
        result = 'none'
        try:
            logger.debug("DNS => %s", domain_name)
            addrs = socket.getaddrinfo(domain_name, 0)
            # logger.info("The address object is:")
            # logger.info(addrs)

            if len(addrs) > 0:
                ip = addrs[0][4][0]
                logger.debug("IP => %s", ip)
                result = ip

        except socket.gaierror:
            logger.error("No DNS response")
            result = 'error'

        # this one works
        try:
            html = urlopen("http://sso-keycloak-maintenance:8080", timeout=0.5)
            # curl -o /dev/null -s -w "%{http_code}\n" http://sso-keycloak-maintenance:8080
        except HTTPError as e:
            print("HTTP error", e)

        except URLError as e:
            print("Opps ! Page not found!", e)

        else:
            print('Yeah !  found ')

        if last_result != result:
            q.put({'event': 'dns', 'result': result,
                  'message': 'IP CHANGE %s' % result})
            last_result = result
        time.sleep(5)
