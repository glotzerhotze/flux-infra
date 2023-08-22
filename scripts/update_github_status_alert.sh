#!/usr/bin/env bash
#
# Rebuild the Github status alert to push the kustomization status back to Github.
# See https://fluxcd.io/docs/guides/notifications/#git-commit-status for details.

set -o errexit
set -o pipefail

# Ensure that we have some locations figured out
SCRIPT_DIR=$(dirname $(realpath $0))
CLUSTERS=${SCRIPT_DIR}/../clusters

for cluster in ${CLUSTERS}/*
  do
    echo "## Scanning cluster ${cluster}"

    # Create the skeleton for the alert config
    TMP_ALERT=$(mktemp)

    cat << EOF > ${TMP_ALERT}
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Alert
metadata:
  name: github-status
  namespace: flux-system
spec:
  providerRef:
    name: github-status
  eventSeverity: info
  eventSources:
EOF

    # Find kustomizations to add to the file
    pushd ${cluster} >/dev/null
    find . -type f -name '*.kustomization.yaml' -print0 | while IFS= read -r -d $'\0' file;
      do
        echo "Found kustomization ${file}"
        NAMESPACE=$(yq e '.metadata.namespace' ${file})
        NAME=$(yq e '.metadata.name' ${file})

        cat << EOF >> ${TMP_ALERT}
    - kind: Kustomization
      name: ${NAME}
      namespace: ${NAMESPACE}
EOF
    done

    echo "Update rendered github-status.alert.yaml"
    mv ${TMP_ALERT} github-status.alert.yaml
    popd >/dev/null
done
