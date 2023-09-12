##
### Policy definitions
##
## Create admin policy in the root namespace
resource "vault_policy" "admin" {
  name   = "admin"
  policy = file("policies/_bootstrap/vault-admin.hcl")
}
