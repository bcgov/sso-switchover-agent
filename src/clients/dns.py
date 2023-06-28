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

        maintenance_mode = is_keycloak_dr_up_and_receiving_traffic(ip, last_result)

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


def is_keycloak_dr_up_and_receiving_traffic(ip: str, last_result: str):
    # If the maintenance page is detected as down, but traffic is still going to the GoldDR cluster
    # It means keycloak DR must be active since traffic only goes to DR if
    # the GSLB health check is passing.

    if (ip == config.get('passive_ip')):
        try:
            html = urlopen("http://sso-keycloak-maintenance:8080", timeout=0.5)
            # curl -o /dev/null -s -w "%{http_code}\n" http://sso-keycloak-maintenance:8080
        except HTTPError as e:
            logger.debug("HTTP error", e)
            return 'error'
        except URLError as e:
            logger.debug("Keycloak Dr Is up")
            return 'keycloak_up'
        else:
            logger.debug('Maintenance Service Up')
            return 'maintenance_up'
        # Add logic to handle first case
    elif (ip == config.get('active_ip')):
        return 'gold_up'
    else:
        return 'error'

# def send_clients_message_dr_in_progress():
#     return False

# def send_clients_message_dr_active_access_restored():
#     return False

# def send_clients_message_dr_resolved_systems_normal(ip: str, prev_ip: str):
#     return False
