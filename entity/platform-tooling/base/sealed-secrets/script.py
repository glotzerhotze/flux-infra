#!/usr/bin/python

import os
import re
import botocore
import botocore.session
from kubernetes import client, config
from aws_secretsmanager_caching import SecretCache, SecretCacheConfig

config.load_incluster_config()
client_core_api = client.CoreV1Api()

aws_access_key_id = os.getenv("AWS_SECRET_KEY_ID")
aws_secret_access_key = os.getenv("AWS_SECRET_ACCESS_KEY")
client_args = {
    "region_name": "eu-central-1"
}

if os.getenv("AWS_SECRET_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY"):
    client_args["aws_access_key_id"] = aws_access_key_id
    client_args["aws_secret_access_key"] = aws_secret_access_key

smsession = botocore.session.get_session()
client = smsession.create_client('secretsmanager', **client_args)


def get_cluster_name(namespace="kube-system"):
    list_cm = client_core_api.list_namespaced_config_map(
            namespace="{}".format(namespace)
        )
    for k in list_cm.items:
        if "kubeadm-config" == k.metadata.name:
            if "clusterName" in k.data['ClusterConfiguration']:
                cluster_name = re.search(r"clusterName: ([\s\S]+)controlPlaneEndpoint",
                                        k.data['ClusterConfiguration']).group(1)
                cluster_name = re.sub("-cluster", "", cluster_name).strip()
            return cluster_name


cluster = get_cluster_name("kube-system")


# get kubernetes aws secrets
def get_secrets_name(namespace="kube-system"):
    secrets = []
    try:
        resp = client_core_api.list_namespaced_secret(
            namespace="{}".format(namespace),
            timeout_seconds=10,
            label_selector="sealedsecrets.bitnami.com/sealed-secrets-key"
        )
        for k in resp.items:
            new_secrets = cluster+"-"+k.metadata.name
            secrets.append(new_secrets)
    except Exception as e:
        print("Error getting Kubernetes secrets \n{}".format(e))
        return None
    return secrets


# get aws Secrets Manager sealedsecrets
def get_aws_secrets():
    aws_secrets = []
    paginator = client.get_paginator('list_secrets')
    page_iterator = paginator.paginate()
    for page in page_iterator:
        for name in page['SecretList']:
            aws_secrets.append(name['Name'])
    return aws_secrets


# get secrets
kubernetes_secrets_list = get_secrets_name("kube-system")
aws_sm_secrets_list = get_aws_secrets()

# compare secrets lists
diff = list(set(kubernetes_secrets_list) - set(aws_sm_secrets_list))


def get_new_sealedssecret(namespace="kube-system", new_name=""):
    try:
        name = re.sub(cluster+"-", "", new_name)
        new_secret_json = client_core_api.read_namespaced_secret(
            namespace="{}".format(namespace),
            name="{}".format(name)
        )
    except Exception as e:
        print("Error getting Kubernetes secrets \n{}".format(e))
        return None
    return new_secret_json


def create_new_secret_manager_secret(name=""):
    new_sm_secret = client.create_secret(
        Name=name,
        SecretString=str(sealedssecret),
        Description="This is value of sealed secret from {}".format(cluster)
    )


# create a file with new SealedSecret
if diff != []:
    b = len(diff)
    for i in range(0, b):
        sealedssecret = get_new_sealedssecret("kube-system", diff[i])
        create_new_secret_manager_secret(diff[i])
else:
    print("There are no new encryption keys")
