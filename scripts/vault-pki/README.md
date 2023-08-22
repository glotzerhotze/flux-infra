# How to use vault with pre-generated PKI setup
If you want to secure the in-cluster vault traffic, you should use a pre-generated PKI infrastructure. This document will help you to create such an infrastructure and put it into your cluster to use by vault.

## Overview of TLS usage
There are several parts that need a TLS certificate. Once we have the proper secret objects `tls-ca` and `tls-server` created, the operator generated pods will start to spin up and get ready.

To create the two secret objects in the namespace `vault` you will have to issue these commands:

```
kubectl -n vault create secret tls tls-ca \
 --cert ./ca/ca.pem  \
 --key ./ca/ca-key.pem

kubectl -n vault --context internal create secret tls tls-server \
  --cert ./server/bare-metal/vault.pem \
  --key ./server/bare-metal/vault-key.pem

kubectl -n vault --context prod create secret tls tls-server \
  --cert ./server/cloud/vault.pem \
  --key ./server/cloud/vault-key.pem

kubectl -n vault --context local create secret tls tls-server \
  --cert ./server/local/vault.pem \
  --key ./server/local/vault-key.pem

```

Remember: the same self-signed CA certificate will be used to secure the vault in `bare-metal` (aka. production) and `cloud` (aka. staging) environments. The `ca.pem` will need to be distributed and trusted by all entities (services and users) that should / will talk to `vault.cloud.klessen.cloud` and `vault.bare-metal.klessen.cloud` endpoints.

Only thing that will be different is the server-certificate that gets used in both environments. With this setup there will be only one CA certificate that need to be distributed to establish a trust-relationship between our vault endpoints and the consumers of these endpoints.

Remember: the `ca-key.pem` file should ALWAYS be keept SECRET! It is only needed if you want to sign (or even create the private key for) other server certificates.

## Create the PKI material to enable encryption
Since we have two environments with differing endpoints for the external VPN availability of vault, we will need to create different certs encoding different URL's via DNS name

### create the global vault CA and self-sign the certificate and key
For the creation of the CA certificate and a private key which will sign it's own key (thus generating the self-signed CA certificate) and all other server-TLS certificates we will have to issue the following command:

```
#generate CA in ./ca
cfssl gencert -initca ca-csr.json | cfssljson -bare ./ca/ca
```

For the command to work, we will have to feed it a certificate-signing-request configuration, which should look like below and can be found in the `ca-csr.json` file:
```
{
  "signing": {
    "default": {
      "expiry": "175200h"
    },
    "profiles": {
      "default": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "175200h"
      }
    }
  }
}
```
With this config-file available, initialisation of the `vault CA` should be possible and corresponding files should be created in the `./ca` folder

### vault.i.klessen.cloud
For the `staging` environment, we need to issues this command
```
#generate global self-signed CA certificate in ./ca folder
cfssl gencert \
  -ca=./ca/ca.pem \
  -ca-key=./ca/ca-key.pem \
  -config=ca-config.json \
  -hostname="vault.staging.klessen.cloud,*.vault-internal,*.vault-internal.vault,*.vault,*.vault.svc,*.vault.svc.cluster.local,localhost,127.0.0.1" \
  -profile=default \
  ca-csr.json | cfssljson -bare ./server/cloud/vault
```

We will additionally need this configuration stored in `ca-config.json` file to tell cfssl how long the certificates should be valid - here we use 20 years, as we encrypt in-cluster traffic between services which won't need periodic certificate roll-overs:
```
{
  "signing": {
    "default": {
      "expiry": "175200h"
    },
    "profiles": {
      "default": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "175200h"
      }
    }
  }
}
```

### vault.prod.klessen.cloud
For the `production` environment, we need to issues this command
```
#generate certificate in ./server/production
cfssl gencert \
  -ca=./ca/ca.pem \
  -ca-key=./ca/ca-key.pem \
  -config=ca-config.json \
  -hostname="vault.prod.klessen.cloud,*.vault-internal,*.vault-internal.vault,*.vault,*.vault.svc,*.vault.svc.cluster.local,localhost,127.0.0.1" \
  -profile=default \
  ca-csr.json | cfssljson -bare ./server/bare-metal/vault
```
We will just re-use the `ca-config.json` from above, as this will only configure the validity-time of the certificates created which we will use for both environments.

### vault.local.klessen.cloud
For the `local` environment, we need to issues this command
```
#generate certificate in ./server/production
cfssl gencert \
  -ca=./ca/ca.pem \
  -ca-key=./ca/ca-key.pem \
  -config=ca-config.json \
  -hostname="vault.local.klessen.cloud,*.vault-internal,*.vault-internal.vault,*.vault,*.vault.svc,*.vault.svc.cluster.local,localhost,127.0.0.1" \
  -profile=default \
  ca-csr.json | cfssljson -bare ./server/local/vault
```
We will just re-use the `ca-config.json` from above, as this will only configure the validity-time of the certificates created which we will use for both environments.