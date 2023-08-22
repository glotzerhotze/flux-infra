#!/usr/bin/env bash

RELEASE_NAME=eck-operator
RELEASE_NAMESPACE=elastic-system

for CRD in $(kubectl get crds --no-headers -o custom-columns=NAME:.metadata.name | grep k8s.elastic.co); do
  kubectl annotate crd "$CRD" meta.helm.sh/release-name="$RELEASE_NAME" --overwrite;
  kubectl annotate crd "$CRD" meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" --overwrite;
  kubectl label crd "$CRD" app.kubernetes.io/managed-by=Helm --overwrite;
done

kubectl delete -n elastic-system \
  serviceaccount/elastic-operator \
  secret/elastic-webhook-server-cert \
  clusterrole.rbac.authorization.k8s.io/elastic-operator \
  clusterrole.rbac.authorization.k8s.io/elastic-operator-view \
  clusterrole.rbac.authorization.k8s.io/elastic-operator-edit \
  clusterrolebinding.rbac.authorization.k8s.io/elastic-operator \
  service/elastic-webhook-server \
  configmap/elastic-operator \
  statefulset.apps/elastic-operator \
  validatingwebhookconfiguration.admissionregistration.k8s.io/elastic-webhook.k8s.elastic.co

flux suspend kustomization elastic-operator-all-in-one
flux resume kustomization eck-operator