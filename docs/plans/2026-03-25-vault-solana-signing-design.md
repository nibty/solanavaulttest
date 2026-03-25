# Vault + Solana Transaction Signing Demo

## Purpose

Demo application that uses HashiCorp Vault's transit secrets engine to hold Ed25519 keys and sign Solana transactions. The private key never leaves Vault. Demonstrates a simple SOL transfer on devnet.

## Architecture

### Components

- **Vault server** — Docker container, transit engine enabled, holds one Ed25519 key
- **Bootstrap script** — Configures Vault on startup: transit engine, key, policy, CIDR-bound token
- **CLI app** — TypeScript script that builds a Solana transfer, signs via Vault, submits to devnet

### Transaction Signing Flow

```
VAULT_TOKEN=<token> npx ts-node src/sign-transfer.ts --to <address> --amount 0.1

1. Fetch public key from Vault GET /v1/transit/keys/guardian-1
2. Base64-decode → 32-byte Solana PublicKey (the "from" address)
3. Build SystemProgram.transfer instruction
4. Serialize transaction message
5. POST /v1/transit/sign/guardian-1 with base64(message)
6. Strip vault:v1: prefix, standard base64-decode → 64-byte Ed25519 signature
7. Attach signature to transaction
8. Submit to Solana devnet
9. Print explorer URL
```

No private key touches the client at any point.

## Vault Configuration

### Transit Engine

- Engine path: `transit`
- Key name: `guardian-1`
- Key type: `ed25519`
- Exportable: no
- Deletion protection: enabled

### Policy (`guardian-1-sign`)

```hcl
path "transit/sign/guardian-1" {
  capabilities = ["update"]
}
path "transit/verify/guardian-1" {
  capabilities = ["update"]
}
path "transit/keys/guardian-1" {
  capabilities = ["read"]
}
```

Grants sign + verify + read-public-key only. No key export, no access to other keys.

### Token

- Policy: `guardian-1-sign`
- TTL: 24h (configurable)
- CIDR bound: `127.0.0.1/32` (Docker-local)

## Docker Setup

Single-service Docker Compose. Vault runs in dev mode (no unsealing). Bootstrap script runs after Vault is ready.

## File Structure

```
hashicorpvaulttest/
├── docker-compose.yml
├── vault/
│   ├── bootstrap.sh
│   └── policy.hcl
├── src/
│   └── sign-transfer.ts
├── package.json
├── tsconfig.json
├── systemd/
│   └── guardian.service    # Reference template only
└── README.md
```

## Systemd Reference

Production token injection via systemd unit environment variable — included as a non-functional template:

```ini
[Service]
Environment="VAULT_ADDR=https://vault.internal:8200"
Environment="VAULT_TOKEN=%d/vault-token"
```

No `.env` files.

## Dependencies

- `@solana/web3.js` — transaction building, devnet connection
- `bs58` — base58 encoding
- `commander` — CLI arguments
- Raw `fetch` — Vault HTTP API (no extra Vault client library needed in Node 18+)

## Key Decisions

- **Vault signs, not the client** — private key never exported
- **Standard base64 signature** — `marshaling_algorithm` only applies to ECDSA; Ed25519 returns `vault:v1:<base64>`, strip prefix and decode
- **Dev mode Vault** — no unsealing for demo simplicity
- **Single key** — demonstrates the pattern without multisig complexity
