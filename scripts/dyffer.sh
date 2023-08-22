#!/bin/bash

# Required tools:
#   - kubernetes-split-yaml: https://github.com/mogensen/kubernetes-split-yaml
#   - dyff: https://github.com/homeport/dyff

set -o pipefail
set -e

shopt -s extglob

# The location of the service in the k8s-manifests repo
# e.g. /Users/dkerwin/Code/k8s-manifests/environments/production/3a/api
OLD=$1

# The location of the flux v2 overlay in the fleet-infra repo
# e.g. /Users/dkerwin/Code/fleet-infra/entity/3a/3a/internal/api
NEW=$2

START_PATH=$(pwd)

echo
echo "► Rendering flux v2 manifests with kustomize"
echo

cd ${NEW}
kustomize build | kubernetes-split-yaml -

echo
echo "► Remove suffix from configMap filename (if any)"
echo

for f in ./generated/*-cm.yaml
do
  if [[ "${f}" =~ -[a-zA-Z0-9]{10}-cm.yaml$ ]]
  then
    echo "Stripping random suffix: ${f} => ${f/-*([0-9a-z])-cm.yaml/-cm.yaml}"
    mv $f ${f/-*([0-9a-z])-cm.yaml/-cm.yaml}
  fi
done

echo
echo "► Remove suffix from secret filename (if any)"
echo

for f in ./generated/*-secret.yaml
do
  if [[ "${f}" =~ -[a-zA-Z0-9]{10}-secret.yaml$ ]]
  then
    echo "Stripping random suffix: ${f} => ${f/-*([0-9a-z])-secret.yaml/-secret.yaml}"
    mv $f ${f/-*([0-9a-z])-secret.yaml/-secret.yaml}
  fi
done

echo
echo "► Converting flux v1 manifests for comparison"
echo

cd ${OLD}
for I in $(ls *.yml *.yaml)
do
  kubernetes-split-yaml $I
done

cd ./generated

echo
echo "► Time for a dyff"
echo

for f in ./*.yaml
do
  if [[ ! -f "${NEW}/generated/${f}" ]]
  then
    echo
    echo "================================================================================================================="
    echo "= !!! No couterpart found for ${f} !!! Dyff skipped. Please check if this is expected"
    echo "================================================================================================================="
    echo
  else
    dyff between -i ${f} ${NEW}/generated/${f}
  fi
done

cd ${START_PATH}

echo
echo "► Cleaning up"
echo

rm -rf ${NEW}/generated ${OLD}/generated

exit 0
