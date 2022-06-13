SHELL := /usr/bin/env bash

.PHONY: install
install:
	poetry self install
	asdf reshim

.PHONY: format
format:
	autopep8 --in-place --recursive src

.PHONY: start
start:
	python src/main.py
