#!/usr/bin/env sh
set -e

export BAO_ADDR="${BAO_ADDR:-http://127.0.0.1:8200}"
export BAO_TOKEN="${BAO_TOKEN:-root-token}"

echo "Waiting for OpenBao..."
until bao status > /dev/null 2>&1; do
  sleep 1
done
echo "OpenBao is ready."

# Enable transit engine (ignore if already enabled)
bao secrets enable transit 2>/dev/null || true

# Create ed25519 key (ignore if already exists)
bao write -f transit/keys/guardian-1 type=ed25519 2>/dev/null || true

# Prevent accidental deletion
bao write transit/keys/guardian-1/config deletion_allowed=false

# Write signing policy
bao policy write guardian-1-sign /vault/config/policy.hcl

# Create a service token scoped to guardian-1
GUARDIAN_TOKEN=$(bao token create \
  -policy=guardian-1-sign \
  -ttl=24h \
  -display-name="guardian-1" \
  -field=token)

# Fetch the public key via HTTP API (avoids jq dependency)
PUBLIC_KEY_B64=$(wget -qO- \
  --header="X-Vault-Token: ${BAO_TOKEN}" \
  "${BAO_ADDR}/v1/transit/keys/guardian-1" \
  | sed 's/.*"public_key":"\([^"]*\)".*/\1/')

# Base58 encode using dc for bignum arithmetic (available in busybox/alpine)
# dc wraps long numbers with backslash-newline; sed joins them back
b58() {
  ALPHA="123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  RAW=$(echo "$1" | base64 -d | od -An -tx1 | tr -d ' \n')
  HEXUP=$(echo "$RAW" | tr 'a-f' 'A-F')

  # Leading zero bytes become leading '1' chars
  LEAD=""
  TMP="$RAW"
  while [ "${TMP#00}" != "$TMP" ]; do
    LEAD="${LEAD}1"
    TMP="${TMP#00}"
  done

  # Convert hex to decimal, joining dc's backslash-newline wrapping
  NUM=$(printf '16i %s p\n' "$HEXUP" | dc | sed ':a;/\\$/N;s/\\\n//;ta')

  # Repeatedly divmod 58 to get base58 digits (LSB first, prepend each)
  OUT=""
  while [ "$NUM" != "0" ]; do
    REM=$(printf '%s 58 %% p\n' "$NUM" | dc | sed ':a;/\\$/N;s/\\\n//;ta')
    NUM=$(printf '%s 58 / p\n' "$NUM" | dc | sed ':a;/\\$/N;s/\\\n//;ta')
    IDX=$((REM + 1))
    C=$(printf '%s' "$ALPHA" | cut -c"${IDX}-${IDX}")
    OUT="${C}${OUT}"
  done
  printf '%s%s\n' "$LEAD" "$OUT"
}

SOLANA_ADDRESS=$(b58 "$PUBLIC_KEY_B64")

echo ""
echo "============================================"
echo "  GUARDIAN-1 SETUP COMPLETE"
echo "============================================"
echo "  Service Token: ${GUARDIAN_TOKEN}"
echo "  Solana Address: ${SOLANA_ADDRESS}"
echo "============================================"
echo ""
echo "  Run the demo:"
echo "  BAO_TOKEN=${GUARDIAN_TOKEN} yarn transfer -- --to <SOLANA_ADDRESS> --amount 0.01"
echo ""
