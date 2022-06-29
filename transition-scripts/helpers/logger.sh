#!/bin/bash

# https://en.wikipedia.org/wiki/ANSI_escape_code
# Black        0;30     Dark Gray     1;30
# Red          0;31     Light Red     1;31
# Green        0;32     Light Green   1;32
# Brown/Orange 0;33     Yellow        1;33
# Blue         0;34     Light Blue    1;34
# Purple       0;35     Light Purple  1;35
# Cyan         0;36     Light Cyan    1;36
# Light Gray   0;37     White         1;37

RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
NO_COLOR="\033[0m"

info() {
    msg="$1"
    echo -e "[$(get_current_cluster):info] ${BLUE}${msg}${NO_COLOR}"
}

warn() {
    msg="$1"
    echo -e "[$(get_current_cluster):warn] ${YELLOW}${msg}${NO_COLOR}"
}

error() {
    msg="$1"
    echo -e "[$(get_current_cluster):error] ${RED}${msg}${NO_COLOR}"
}
