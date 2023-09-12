# cockroachdb-operator

08/2023
there exist two options for cockroachDB:

1. use the k8s-operator like we do here
2. use the helm-chart that will NOT use an operator, but rather rolls out actual DB clusters instead

```yaml
currentVersion: v2.11.0
downloadLinks:
- https://raw.githubusercontent.com/cockroachdb/cockroach-operator/v2.11.0/install/crds.yaml
- https://raw.githubusercontent.com/cockroachdb/cockroach-operator/v2.11.0/install/operator.yaml
```

No base-layer being used - rather for de-coupling we stick to individual full-release definitions for an environment.

There is a dependency on `v2.9.0` for k8s-1.20.x clusters - as the cockroach-operator in `v2.10.0`:

```
Upgrade the underlying k8s dependencies from 1.20 to 1.21 to support operator installation on k8s 1.25+.
```

[official changelog](https://github.com/cockroachdb/cockroach-operator/blob/master/CHANGELOG.md)
