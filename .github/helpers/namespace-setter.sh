#!/bin/bash
set -e

if [ "$#" -lt 2 ]; then
    exit 1
fi
project=$1
env=$2

if [ "$project" == "SANDBOX" ]; then
    namespace="e4ca1d-$env"
elif [ "$project" == "OLD-SANDBOX2" ]; then
    namespace="c6af30-$env"
elif [ "$project" == "PRODUCTION" ]; then
    namespace="eb75ad-$env"
else
    echo "Invalid project name '$project' entered"
    exit 1
fi
# export namespace="c6af30-dev"
echo "NAMESPACE=$namespace" >> "$GITHUB_ENV"
