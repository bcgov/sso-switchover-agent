SHELL := /usr/bin/env bash
NAMESPACE="c6af30-tools"

.PHONY: install
install:
	helm install uptime-checker . -n "${NAMESPACE}" -f values-${NAMESPACE}.yaml

.PHONY: upgrade
upgrade:
	helm upgrade --install uptime-checker . -n "${NAMESPACE}" -f values-${NAMESPACE}.yaml
