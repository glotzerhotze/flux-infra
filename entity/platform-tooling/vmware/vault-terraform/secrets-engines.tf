##
### Enable secrets engines
##
## Enable K/V v2 secrets engine at 'secrets'
resource "vault_mount" "secrets" {
  path = "secrets"
  type = "kv-v2"
}
