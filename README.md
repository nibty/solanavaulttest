# Vault + Solana Transaction Signing Demo

Signs Solana transactions using HashiCorp Vault's transit secrets engine. The Ed25519 private key never leaves Vault.

## Quick Start

### 1. Start Vault

```bash
docker compose up -d
docker compose logs bootstrap
```

Copy the `Service Token` from the bootstrap output.

### 2. Install dependencies

```bash
yarn install
```

### 3. Fund the Vault-derived address

The bootstrap output shows the Solana address. Fund it on devnet:

```bash
solana airdrop 1 <SOLANA_ADDRESS> --url devnet
```

### 4. Send a transfer

```bash
VAULT_TOKEN=<service-token> yarn transfer -- --to <RECIPIENT_ADDRESS> --amount 0.01
```

## How It Works

1. Vault's transit engine holds an Ed25519 key (`guardian-1`)
2. The CLI fetches the public key from Vault — derives the Solana address
3. Builds a SOL transfer transaction
4. Sends the serialized message to Vault for signing
5. Vault returns the Ed25519 signature (private key never leaves Vault)
6. CLI attaches the signature and submits to Solana devnet

## Architecture

- `vault/policy.hcl` — Scoped policy: sign + verify + read for `guardian-1` only
- `vault/bootstrap.sh` — Configures transit engine, key, policy, and service token
- `src/vault.ts` — Vault HTTP API client (public key fetch + signing)
- `src/sign-transfer.ts` — CLI that builds and submits the signed transaction
- `systemd/guardian.service` — Reference template for production deployment

## Production Notes

- Tokens are CIDR-bound and have TTL — rotate every N days
- Inject `VAULT_TOKEN` via systemd environment variable, not `.env` files
- See `systemd/guardian.service` for the deployment template
