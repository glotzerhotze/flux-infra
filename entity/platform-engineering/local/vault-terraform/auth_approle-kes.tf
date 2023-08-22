##
### Backend definitions
##
## approle backend to store all the minio related information
resource "vault_auth_backend" "kes" {
  type        = "approle"
  path        = "approle/kes"
  description = "this backend will hold all secrets required by the minio KES application server"
}

##
### Role definitions
##
## Role for minio to allow SSE for the storage cluster
resource "vault_approle_auth_backend_role" "kes" {
  backend               = vault_auth_backend.kes.path
  role_name             = "kes"
  token_policies        = ["kes", "default"]
  secret_id_num_uses    = 0
  token_num_uses        = 0
  token_period          = 5
}
