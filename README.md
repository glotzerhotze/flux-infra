# dev-infra-base
development infrastructure base repository

## how to use this repo?
this repo serves as a starting point for your own local development environment.

start by cloning this repo onto your machine.

next, you should create a private github-repository for your own local cluster


bootstrap from personal repo:
```bash
flux bootstrap github --owner=${MY_GITHUB_NAME} --repository=${MY_GITHUB_REPO} --path=clusters/local --branch=main --read-write-key --hostname github.com --personal
```

bootstrap from company repo:
```bash
 flux bootstrap github --owner=${MY_GITHUB_ORG} --repository=${MY_GITHUB_REPO} --path=clusters/local --branch=main --read-write-key --team ${MY_GITHUB_TEAM} --hostname github.com
```


