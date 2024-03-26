import unittest
from unittest.mock import patch

from logic import action_dispatcher

# The GSLB logic is covered here:
# /docs/switchover-logic-and-the-gslb.md
active_ip = "1.0.0.1"
passive_ip = "1.0.0.2"
error_code = "error"


class TestTheDispatcher(unittest.TestCase):
    # DNS record changes to Gold Cluster
    def test_action_dispatcher_gold_to_gold(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(active_ip, active_ip, active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    def test_action_dispatcher_golddr_to_gold(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(active_ip, passive_ip, active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_called_once_with(False)
            mock_rocket_chat.assert_not_called()

    def test_action_dispatcher_none_to_gold(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(active_ip, 'undefined', active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    # DNS record changes to GoldDR Cluster

    def test_action_dispatcher_gold_to_golddr(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(passive_ip, active_ip, active_ip, passive_ip)
            mock_dispatch_action.assert_called_once()
            mock_css_maintenance.assert_called_once_with(True)
            mock_rocket_chat.assert_not_called()

    def test_action_dispatcher_golddr_to_golddr(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(passive_ip, passive_ip, active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    def test_action_dispatcher_none_to_golddr(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(passive_ip, 'unknown', active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    # DNS record changes to ERROR (no dns resolved)

    def test_action_dispatcher_gold_to_error(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(error_code, active_ip, active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    def test_action_dispatcher_golddr_to_error(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(error_code, passive_ip, active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    def test_action_dispatcher_none_to_error(self):
        with patch('logic.dispatch_action_by_id') as mock_dispatch_action, \
                patch('logic.dispatch_rocketchat_webhook') as mock_rocket_chat, \
                patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance:

            action_dispatcher(error_code, 'unknown', active_ip, passive_ip)
            mock_dispatch_action.assert_not_called()
            mock_css_maintenance.assert_not_called()
            mock_rocket_chat.assert_not_called()

    def test_skip_css_maintenance_action_if_dns_is_resolved_to_passive_ip(self):
        with patch('logic.dispatch_css_maintenance_action') as mock_css_maintenance, \
                patch('logic.check_dns_by_env', return_value=True) as mock_check_dns_by_env:
            action_dispatcher(active_ip, passive_ip, active_ip, passive_ip)
            mock_check_dns_by_env.assert_called_once_with('dev', passive_ip)
            mock_css_maintenance.assert_not_called()
