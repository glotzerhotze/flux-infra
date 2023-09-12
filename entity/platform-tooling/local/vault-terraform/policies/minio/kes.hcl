path "secrets/data/minio/*" {
  capabilities = ["create", "read"]
}

path "secrets/metadata/minio/*" {
  capabilities = [ "list", "delete"]
}
