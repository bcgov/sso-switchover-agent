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
    last_maintenance_mode = "unknown"
    while True:
        result = 'none'
        maintenance_mode = "unknown"
        try:
            logger.debug("DNS => %s", domain_name)
            addrs = socket.getaddrinfo(domain_name, 0)

            if len(addrs) > 0:
                ip = addrs[0][4][0]
                logger.debug("IP => %s", ip)
                result = ip

        except socket.gaierror:
            logger.error("No DNS response")
            result = 'error'

        maintenance_mode = is_keycloak_dr_up_and_receiving_traffic(result)

        if last_result != result:
            q.put({'event': 'dns', 'result': result,
                  'message': 'IP CHANGE %s' % result})
            last_result = result

        if maintenance_mode != last_maintenance_mode and maintenance_mode != 'error':
            if last_maintenance_mode != "unknown":
                q.put({'event': 'maintenance', 'maintenance_mode': maintenance_mode,
                       'message': 'Maintenance mode CHANGE %s' % maintenance_mode})
            last_maintenance_mode = maintenance_mode

        time.sleep(5)


def is_keycloak_dr_up_and_receiving_traffic(ip: str):
    # If the maintenance page is detected as down, but traffic is still going to the GoldDR cluster
    # It means keycloak DR must be active since traffic only goes to DR if
    # the GSLB health check is passing.
    if (ip == config.get('passive_ip')):
        try:
            html = urlopen("http://sso-keycloak-maintenance:8080", timeout=0.5)
        except HTTPError as e:
            logger.debug("HTTP error", e)
            return 'error'
        except URLError as e:
            logger.debug("Keycloak Dr Is up")
            return 'keycloak_up'
        else:
            logger.debug('Maintenance Service Up')
            return 'maintenance_up'
    elif (ip == config.get('active_ip')):
        return 'gold_up'
    else:
        return 'error'


def fetch_domain_by_env(env, prod):
    switcher = {
        "sandbox-dev": "dev.sandbox.loginproxy.gov.bc.ca",
        "sandbox-test": "test.sandbox.loginproxy.gov.bc.ca",
        "sandbox-prod": "sandbox.loginproxy.gov.bc.ca",
        "dev": "dev.loginproxy.gov.bc.ca",
        "test": "test.loginproxy.gov.bc.ca",
        "prod": "loginproxy.gov.bc.ca",
    }
    if prod:
        return switcher.get(env, "")
    else:
        return switcher.get("%s-%s" % ("sandbox", env), "")


def check_dns_by_env(env, mode):
    print('hello')
    try:
        ip_address = socket.gethostbyname(fetch_domain_by_env(env, "sandbox" not in config.get('domain_name')))
        if(config.get(mode) == ip_address):
            return True
        return False
    except socket.gaierror:
        logger.error("Invalid domain or could not resolve the IP address.")
        return 'error'
