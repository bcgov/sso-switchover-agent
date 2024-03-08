#!/bin/bash
set -e

if [ "$#" -lt 2 ]; then
    echo "Invalid number of parameters provided, expected 2"
    exit 1
fi
project=$1
env=$2

if [ "$project" == "SANDBOX" ]; then
    urlsuffix="sandbox.loginproxy.gov.bc.ca"
elif [ "$project" == "PRODUCTION" ]; then
    urlsuffix="loginproxy.gov.bc.ca"
else
    echo "Invalid project name, '$project', entered"
    exit 1
fi

if [ "$env" == "dev" ] || [ "$env" == "test" ]; then
    url="$env.$urlsuffix"
elif [ "$env" == "prod" ]; then
    url=$urlsuffix
else
    echo "Invalid project env, '$env', entered"
    exit 1
fi

echo "KEYCLOAK_URL=$url" >> "$GITHUB_ENV"
