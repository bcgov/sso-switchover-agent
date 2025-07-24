import socket
import asyncio
import logging
import time
import json
import requests

from multiprocessing import Queue
from config import config

from urllib.request import urlopen
from urllib.error import *

logger = logging.getLogger(__name__)

passive_ip = config.get('passive_ip')
try:
    delay_switchover_by_secs = int(config.get('delay_switchover_by_secs'))
except BaseException:
    logger.error("Invalid delay time, using zero as default.")
    delay_switchover_by_secs = 0

sleep_time = 5


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
    switchover_waiting = False
    time_index = 0
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

        # Pause the switchover logic to prevent short failovers
        if last_result != result and not switchover_waiting:
            switchover_waiting = True
            time_index = 0
            if delay_switchover_by_secs > 0 and last_result != "unknown":
                q.put({'event': 'team_rocketchat', 'message': 'A change in DNS detected.', 'delay': delay_switchover_by_secs})
        # Unpause if the original state is back
        elif last_result == result and switchover_waiting:
            switchover_waiting = False
            time_index = 0

        if switchover_waiting:
            if (delay_switchover_by_secs <= sleep_time * time_index):
                switchover_waiting = False
                time_index = 0
            else:
                logger.debug(f"Switchover paused for {sleep_time * time_index} of {delay_switchover_by_secs} seconds")
                time_index += 1

        if not switchover_waiting:
            maintenance_mode = is_keycloak_dr_up_and_receiving_traffic(result)

            if last_result != result:
                message = f'IP CHANGE {result}'

                if result == 'error':
                    golddr_network_working = test_external_network()
                    if not golddr_network_working:
                        message = 'The GoldDr Network appears to be down. Gold Keycloak may still be up and healthy.'
                    else:
                        message = 'GSLB is not resolving Gold or GoldDR IPs.'

                q.put({'event': 'dns', 'result': result,
                       'message': message})
                last_result = result

            if maintenance_mode != last_maintenance_mode and maintenance_mode != 'error':
                if last_maintenance_mode != "unknown":
                    q.put({'event': 'maintenance', 'maintenance_mode': maintenance_mode,
                           'message': 'Maintenance mode CHANGE %s' % maintenance_mode})
                last_maintenance_mode = maintenance_mode

        time.sleep(sleep_time)


def is_keycloak_dr_up_and_receiving_traffic(ip: str):
    maintenance_page_content = "Sorry for the inconvenience but we&rsquo;re performing some maintenance at the moment."
    # If the maintenance page is detected as down, but traffic is still going to the GoldDR cluster
    # It means keycloak DR must be active since traffic only goes to DR if
    # the GSLB health check is passing.
    if (ip == config.get('passive_ip')):
        try:
            keycloak_dr = f"https://sso-keycloak-{config.get('namespace')}.apps.golddr.devops.gov.bc.ca/auth/realms/master/.well-known/openid-configuration"
            response = urlopen(keycloak_dr, timeout=1.5)
            if 'application/json' in response.headers.get('Content-Type', ''):
                data = json.load(response)
            else:
                data = {}

            if "issuer" in data:
                logger.debug("Keycloak Dr Is up")
                return 'keycloak_up'
            elif maintenance_page_content in response.read().decode('utf-8'):
                logger.debug('Maintenance Service Up')
                return 'maintenance_up'
            else:
                logger.error("The keycloak dr health check isn't resolving in the json payload or maintenance page is down.")
                return 'error'
        except Exception as err:
            logger.debug("Unable to resolve keycloak dr.")
            logging.error('Error at %s', 'division', exc_info=err)
            return 'error'

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


def check_dns_by_env(env, ip):
    try:
        ip_address = socket.gethostbyname(fetch_domain_by_env(env, "sandbox" not in config.get('domain_name')))
        if (ip == ip_address):
            return True
        return False
    except socket.gaierror:
        logger.error("Invalid domain or could not resolve the IP address.")
        return 'error'


def test_external_network():
    agent_network_up = False
    try:
        # Use the google public DNS as a way of testing that the
        # switchover agent's network is up
        x = requests.get('https://8.8.8.8', timeout=2.5)
        agent_network_up = x.ok
    except Exception as err:
        logging.error('Error at %s', 'division', exc_info=err)

    return agent_network_up
