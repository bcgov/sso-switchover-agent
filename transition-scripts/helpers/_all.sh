#!/bin/bash

this="${BASH_SOURCE[0]}"
pwd=$(dirname "$this")

for f in "$pwd"/*; do
  [ "$this" == "$f" ] && continue # skip itself
  [ -d "$f" ] && continue       # skip directories
  [ -L "${f%/}" ] && continue   # skip symlinks

  echo "$f"

  # shellcheck disable=SC1090
  source "$f"
done
