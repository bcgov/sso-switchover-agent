SHELL := /usr/bin/env bash

.PHONY: install
install:
	poetry self install
	asdf reshim

# support install packages outlined in `pyproject.toml` via pip.
# it is useful to install the packages in `pip`'s target directory
# in case `poetry` downloads them elsewhere.
.PHONY: install-pip
install-pip:
	pip install -r <(poetry export)
	asdf reshim

.PHONY: format
format:
	autopep8 --in-place --recursive src

.PHONY: start
start:
	python src/main.py
