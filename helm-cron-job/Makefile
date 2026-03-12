SHELL := /usr/bin/env bash
NAMESPACE="eb75ad-tools"

.PHONY: install
install:
	helm install kc-dr-cron-job . -n "${NAMESPACE}" -f values-${NAMESPACE}.yaml

.PHONY: upgrade
upgrade:
	helm upgrade --install kc-dr-cron-job . -n "${NAMESPACE}" -f values-${NAMESPACE}.yaml
