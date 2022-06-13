import logging
import time

from multiprocessing import Queue
from config import config
from python_hosts import Hosts, HostsEntry

logger = logging.getLogger(__name__)

active_entry = HostsEntry(entry_type='ipv4', address=config.get('active_ip'), names=[config.get('domain_name')])
passive_entry = HostsEntry(entry_type='ipv4', address=config.get('passive_ip'), names=[config.get('domain_name')])


def set_active_hosts():
    hosts = Hosts()
    hosts.remove_all_matching(name=config.get('domain_name'))
    hosts.add([active_entry])
    hosts.write()


def set_passive_hosts():
    hosts = Hosts()
    hosts.remove_all_matching(name=config.get('domain_name'))
    hosts.add([passive_entry])
    hosts.write()


def test_queues(queue: Queue, processes: list):
    time.sleep(5)
    set_passive_hosts()
    time.sleep(5)

    last_item = ""
    while queue.qsize() > 0:
        last_item = queue.get()

    queue.put("success_" if last_item['result'] == config.get('passive_ip') else "failure")

    for process in processes:
        if process._popen is not None:
            process.terminate()
