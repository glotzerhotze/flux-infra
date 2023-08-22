#!/usr/bin/env bash

set -o errexit

echo "===== YAML validation ====="
echo

find . -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating $file"
    yq e 'true' "$file" > /dev/null
done
