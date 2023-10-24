provider "vault" {
  # It is strongly recommended to configure this provider through the
  # environment variables and/or disable TLS checks (not recommended)
  #    - VAULT_ADDR="https://vault.prod.klessen.cloud
  #    - VAULT_TOKEN="<admin-token-from-1password>"
  #    - VAULT_CACERT="./ca/ca.pem"
  #    - VAULT_SKIP_VERIFY="true"
  address = "https://vault.vault:8200"
  skip_tls_verify = "true"
}
