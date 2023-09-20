# flux-infra
development infrastructure base repository for flux deployments

## how to use this repository?
this repo serves as a starting point for your own local development environment using kind, cilium and flux

start by cloning this repo onto your machine.

next, you should create a private github-repository to deploy flux and several applications onto your own cluster.

use this repository as an example and starting point.

## how to create a local kind-cluster?
there is a script `./scripts/local_kind_cluster.sh` that should help you to get started with a local k8s environment based on kind and cilium.

please be aware that cilium is configured to run in direct-routing mode without kube-proxy relying purely on eBPF.

you **NEED** to fill in the gaps with your own information (aka. github-token, repository owner, repository name) - you might have to adapt some settings to your environment.

## how to use this elsewhere? cloud? on-prem?
as long as you bring a working cluster (CNI included) this repository will deploy without problems if you bootstrap flux and point it at your forked repository.

## bootstrapping flux for deployment automation

bootstrap from personal repo:
```bash
flux bootstrap github --owner=${MY_GITHUB_NAME} --repository=${MY_GITHUB_REPO} --path=clusters/local --branch=main --read-write-key --hostname github.com --personal
```

bootstrap from company repo:
```bash
 flux bootstrap github --owner=${MY_GITHUB_ORG} --repository=${MY_GITHUB_REPO} --path=clusters/local --branch=main --read-write-key --team ${MY_GITHUB_TEAM} --hostname github.com
```

# license disclaimer
this code-base is structured and based on the original works of those entities mentioned in the `LICENSE`
this code-base should serve as a research project aiming for collaboration with the community and developing gitops best-practices

