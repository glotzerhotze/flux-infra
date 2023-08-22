#!/usr/bin/env bash

# This script downloads the Flux OpenAPI schemas, then it validates the
# Flux custom resources and the kustomize overlays using kubeval.
# This script is meant to be run locally and in CI before the changes
# are merged on the main branch that's synced by Flux.

# Copyright 2020 The Flux authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script is meant to be run locally and in CI to validate the Kubernetes
# manifests (including Flux custom resources) before changes are merged into
# the branch synced by Flux in-cluster.

# Prerequisites
# - yq v4.6
# - kustomize v4.1
# - kubeval v0.15

set -o errexit

# Copy of https://github.com/yannh/kubeconform/blob/master/scripts/openapi2jsonschema.py
SCHEMA_CONVERTER="$(dirname $(realpath "$0"))/openapi2jsonschema.py"

echo "===== Downloading Flux OpenAPI schemas ====="
echo

# flux
mkdir -p /tmp/flux-crd-schemas/master-standalone-strict
curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict

# cilium
mkdir -p /tmp/cilium-crd-schemas

# elasticsearch
mkdir -p /tmp/eck-crd-schemas

# kubegres
mkdir -p /tmp/kubegres-crd-schemas

echo "===== Schema conversion to comply with kubeconform ====="
echo

# flux: Renaming the schemas
echo "Flux filename conversion"
find /tmp/flux-crd-schemas/master-standalone-strict -type f -name '*.json' -print0 | while IFS= read -r -d $'\0' file;
  do
    NEW_NAME=$(basename ${file} | sed "s/-.*-/-/g")
    mv -v ${file} /tmp/flux-crd-schemas/master-standalone-strict/${NEW_NAME}
  done

# cilium: convert the YAML CRDs to JSON schemas
echo "Cilium schema transformation"
pushd /tmp/cilium-crd-schemas/
for file in ciliumclusterwidenetworkpolicies ciliumendpoints ciliumexternalworkloads ciliumidentities ciliumlocalredirectpolicies ciliumnetworkpolicies ciliumnodes
  do
    python "$SCHEMA_CONVERTER" "https://raw.githubusercontent.com/cilium/cilium/master/pkg/k8s/apis/cilium.io/client/crds/v2/$file.yaml"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
  done
popd

# eck: convert YAML CRD to JSON schemas
echo "ECK schema transformation"
pushd /tmp/eck-crd-schemas/
python "$SCHEMA_CONVERTER" https://raw.githubusercontent.com/elastic/cloud-on-k8s/master/config/crds/v1/all-crds.yaml
if [[ ${PIPESTATUS[0]} != 0 ]]; then
  exit 1
fi
popd

# kubegres: convert YAML CRD to JSON schemas
echo "Kubegres schema transformation"
pushd /tmp/kubegres-crd-schemas/
python "$SCHEMA_CONVERTER" https://raw.githubusercontent.com/reactive-tech/kubegres/main/config/crd/bases/kubegres.reactive-tech.io_kubegres.yaml
if [[ ${PIPESTATUS[0]} != 0 ]]; then
  exit 1
fi
popd

# mirror kustomize-controller build options
kustomize_flags="--load-restrictor=LoadRestrictionsNone --reorder=legacy"
kustomize_config="kustomization.yaml"

MODE=$1

if [[ "x${MODE}" == "xpia" ]]; then
  COMMAND="find ./entity/pia -type f -name $kustomize_config -print0"
elif [[ "x${MODE}" == "x3a" ]]; then
  COMMAND="find ./entity/3a -type f -name $kustomize_config -print0"
else
  COMMAND="find . -type f -name $kustomize_config -not -path './entity/3a/*' -not -path './entity/pia/*' -not -path './clusters/*' -print0"
fi

echo "===== Validating kustomize overlays ====="
eval $COMMAND | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating kustomization ${file/%$kustomize_config}"
    kustomize build "${file/%$kustomize_config}" $kustomize_flags | \
      kubeconform -strict -summary -kubernetes-version 1.19.0 -exit-on-error -skip CustomResourceDefinition \
        -schema-location default \
        -schema-location '/tmp/flux-crd-schemas/master-standalone-strict/{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json' \
        -schema-location '/tmp/cilium-crd-schemas/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json' \
        -schema-location '/tmp/eck-crd-schemas/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json' \
        -schema-location '/tmp/kubegres-crd-schemas/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json'
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
done
