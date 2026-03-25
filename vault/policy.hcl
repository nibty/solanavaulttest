# Guardian-1 signing policy
# Grants sign, verify, and public key read — no key export, no other keys.

path "transit/sign/guardian-1" {
  capabilities = ["update"]
}

path "transit/verify/guardian-1" {
  capabilities = ["update"]
}

path "transit/keys/guardian-1" {
  capabilities = ["read"]
}
