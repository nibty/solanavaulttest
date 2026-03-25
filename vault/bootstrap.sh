#!/usr/bin/env sh
set -e

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root-token}"

echo "Waiting for Vault..."
until vault status > /dev/null 2>&1; do
  sleep 1
done
echo "Vault is ready."

# Enable transit engine (ignore if already enabled)
vault secrets enable transit 2>/dev/null || true

# Create ed25519 key (ignore if already exists)
vault write -f transit/keys/guardian-1 type=ed25519 2>/dev/null || true

# Prevent accidental deletion
vault write transit/keys/guardian-1/config deletion_allowed=false

# Write signing policy
vault policy write guardian-1-sign /vault/config/policy.hcl

# Create a service token scoped to guardian-1
GUARDIAN_TOKEN=$(vault token create \
  -policy=guardian-1-sign \
  -ttl=24h \
  -display-name="guardian-1" \
  -field=token)

# Fetch the public key for display via HTTP API (avoids jq dependency)
PUBLIC_KEY_B64=$(wget -qO- \
  --header="X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/transit/keys/guardian-1" \
  | sed 's/.*"public_key":"\([^"]*\)".*/\1/')

echo ""
echo "============================================"
echo "  GUARDIAN-1 SETUP COMPLETE"
echo "============================================"
echo "  Service Token: ${GUARDIAN_TOKEN}"
echo "  Public Key (b64): ${PUBLIC_KEY_B64}"
echo "============================================"
echo ""
echo "  Run the demo:"
echo "  VAULT_TOKEN=${GUARDIAN_TOKEN} yarn transfer -- --to <SOLANA_ADDRESS> --amount 0.01"
echo ""
