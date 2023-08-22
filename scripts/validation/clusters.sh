#!/usr/bin/env bash

set -o errexit

echo "===== Downloading Flux OpenAPI schemas ====="
echo

# flux
mkdir -p /tmp/flux-crd-schemas/master-standalone-strict
curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict

echo "===== Schema conversion to comply with kubeconform ====="
echo

# flux: Renaming the schemas
echo "Flux filename conversion"
find /tmp/flux-crd-schemas/master-standalone-strict -type f -name '*.json' -print0 | while IFS= read -r -d $'\0' file;
  do
    NEW_NAME=$(basename ${file} | sed "s/-.*-/-/g")
    mv -v ${file} /tmp/flux-crd-schemas/master-standalone-strict/${NEW_NAME}
  done

echo "===== Validating flux clusters ====="

find ./clusters -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating ${file}"
    kubeconform -strict -summary -kubernetes-version 1.19.0 -exit-on-error -skip CustomResourceDefinition \
      -ignore-filename-pattern increase_kustomize_concurrency.yaml \
      -schema-location default \
      -schema-location '/tmp/flux-crd-schemas/master-standalone-strict/{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json' \
      "$file"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
done
