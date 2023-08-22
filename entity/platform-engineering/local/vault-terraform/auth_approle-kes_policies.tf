##
### Policy definitions
##
## Policy to allow SSE in a minio-context
resource "vault_policy" "kes" {
  name   = "kes"
  policy = file("policies/minio/kes.hcl")
}
