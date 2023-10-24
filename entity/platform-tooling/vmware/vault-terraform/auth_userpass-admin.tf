##
### Backend definitions
##
## enable userpass backend for plain users
resource "vault_auth_backend" "local" {
  type = "userpass"
  path = "userpass/local"
}

##
### Role definitions
##
## Create admin user
resource "vault_generic_endpoint" "admin" {
  depends_on           = [vault_auth_backend.local]
  path                 = "auth/userpass/local/users/admin"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "policies": ["default", "admin"],
  "password": "m7h9PXR3eECHzbbKjMdgLAfCceuYgiqs"
}
EOT
}
