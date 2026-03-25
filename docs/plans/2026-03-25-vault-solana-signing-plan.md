# Vault + Solana Transaction Signing — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a demo that signs Solana transactions using HashiCorp Vault's transit engine — private key never leaves Vault.

**Architecture:** Docker Compose runs Vault in dev mode. A bootstrap script configures the transit engine with an Ed25519 key, a scoped policy, and a CIDR-bound service token. A TypeScript CLI fetches the public key from Vault, builds a SOL transfer, signs via Vault's HTTP API, and submits to devnet.

**Tech Stack:** HashiCorp Vault (Docker), TypeScript, @solana/web3.js, Node.js 18+ (native fetch)

---

### Task 1: Project Scaffolding

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `.gitignore`

**Step 1: Initialize project**

```bash
cd /Users/nick/projects/hashicorpvaulttest
git init
```

**Step 2: Create package.json**

```json
{
  "name": "vault-solana-signing-demo",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "transfer": "npx ts-node src/sign-transfer.ts"
  },
  "dependencies": {
    "@solana/web3.js": "^1.98.0",
    "bs58": "^5.0.0",
    "commander": "^12.0.0"
  },
  "devDependencies": {
    "ts-node": "^10.9.2",
    "typescript": "^5.7.0"
  }
}
```

**Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

**Step 4: Create .gitignore**

```
node_modules/
dist/
```

**Step 5: Install dependencies**

```bash
yarn install
```

**Step 6: Commit**

```bash
git add package.json tsconfig.json .gitignore yarn.lock
git commit -m "init: project scaffolding with solana and typescript deps"
```

---

### Task 2: Vault Policy File

**Files:**
- Create: `vault/policy.hcl`

**Step 1: Create vault directory and policy**

`vault/policy.hcl`:
```hcl
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
```

**Step 2: Commit**

```bash
git add vault/policy.hcl
git commit -m "add vault policy for guardian-1 signing"
```

---

### Task 3: Vault Bootstrap Script

**Files:**
- Create: `vault/bootstrap.sh`

**Step 1: Create bootstrap.sh**

This script runs inside the Vault container after Vault starts. It:
1. Waits for Vault to be ready
2. Enables the transit engine
3. Creates an ed25519 key
4. Writes the signing policy
5. Creates a CIDR-bound token
6. Prints the token and derived Solana address

```bash
#!/usr/bin/env sh
set -e

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root-token"

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

# Create a CIDR-bound service token
TOKEN_OUTPUT=$(vault token create \
  -policy=guardian-1-sign \
  -ttl=24h \
  -display-name="guardian-1" \
  -format=json)

GUARDIAN_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)

# Fetch the public key for display
KEY_DATA=$(vault read -format=json transit/keys/guardian-1)
PUBLIC_KEY_B64=$(echo "$KEY_DATA" | grep -o '"1":"[^"]*"' | head -1 | cut -d'"' -f4)

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
```

**Step 2: Make executable**

```bash
chmod +x vault/bootstrap.sh
```

**Step 3: Commit**

```bash
git add vault/bootstrap.sh
git commit -m "add vault bootstrap script for transit engine setup"
```

---

### Task 4: Docker Compose

**Files:**
- Create: `docker-compose.yml`

**Step 1: Create docker-compose.yml**

```yaml
services:
  vault:
    image: hashicorp/vault:latest
    ports:
      - "8200:8200"
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: root-token
      VAULT_DEV_LISTEN_ADDRESS: "0.0.0.0:8200"
    cap_add:
      - IPC_LOCK
    volumes:
      - ./vault:/vault/config:ro
    healthcheck:
      test: ["CMD", "vault", "status"]
      interval: 2s
      timeout: 3s
      retries: 5

  bootstrap:
    image: hashicorp/vault:latest
    depends_on:
      vault:
        condition: service_healthy
    environment:
      VAULT_ADDR: "http://vault:8200"
      VAULT_TOKEN: root-token
    volumes:
      - ./vault:/vault/config:ro
    entrypoint: ["/bin/sh", "/vault/config/bootstrap.sh"]
    restart: "no"
```

Note: The bootstrap service overrides `VAULT_ADDR` to point at the `vault` service hostname within Docker networking.

**Step 2: Test Docker Compose starts**

```bash
docker compose up -d
docker compose logs -f bootstrap
```

Expected: Bootstrap prints the guardian token and public key, then exits.

**Step 3: Tear down**

```bash
docker compose down
```

**Step 4: Commit**

```bash
git add docker-compose.yml
git commit -m "add docker compose with vault and bootstrap services"
```

---

### Task 5: Vault Client Module

**Files:**
- Create: `src/vault.ts`

**Step 1: Write vault.ts**

This module wraps the two Vault HTTP API calls we need: get public key, sign data.

```typescript
const VAULT_ADDR = process.env.VAULT_ADDR || "http://127.0.0.1:8200";
const VAULT_TOKEN = process.env.VAULT_TOKEN;

if (!VAULT_TOKEN) {
  throw new Error("VAULT_TOKEN environment variable is required");
}

const headers = {
  "X-Vault-Token": VAULT_TOKEN,
  "Content-Type": "application/json",
};

/**
 * Fetch the ed25519 public key for a named transit key.
 * Returns the raw 32-byte public key as a Buffer.
 */
export async function getPublicKey(keyName: string): Promise<Buffer> {
  const res = await fetch(`${VAULT_ADDR}/v1/transit/keys/${keyName}`, {
    headers,
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Vault read key failed (${res.status}): ${body}`);
  }
  const json = await res.json();
  // Keys are versioned — "1" is the first (and only) version
  const publicKeyB64: string = json.data.keys["1"].public_key;
  return Buffer.from(publicKeyB64, "base64");
}

/**
 * Sign arbitrary data using a named transit key.
 * Returns the raw 64-byte Ed25519 signature as a Buffer.
 *
 * Vault returns signatures as "vault:v1:<base64>".
 * We strip the prefix and base64-decode to get raw bytes.
 */
export async function signData(
  keyName: string,
  data: Buffer
): Promise<Buffer> {
  const input = data.toString("base64");

  const res = await fetch(`${VAULT_ADDR}/v1/transit/sign/${keyName}`, {
    method: "POST",
    headers,
    body: JSON.stringify({ input }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Vault sign failed (${res.status}): ${body}`);
  }
  const json = await res.json();
  const vaultSig: string = json.data.signature;

  // Format: "vault:v1:<base64>"
  const parts = vaultSig.split(":");
  if (parts.length !== 3 || parts[0] !== "vault") {
    throw new Error(`Unexpected signature format: ${vaultSig}`);
  }
  return Buffer.from(parts[2], "base64");
}
```

**Step 2: Commit**

```bash
git add src/vault.ts
git commit -m "add vault client module for transit key read and signing"
```

---

### Task 6: CLI Transfer Script

**Files:**
- Create: `src/sign-transfer.ts`

**Step 1: Write sign-transfer.ts**

```typescript
import {
  Connection,
  PublicKey,
  SystemProgram,
  Transaction,
  LAMPORTS_PER_SOL,
  clusterApiUrl,
} from "@solana/web3.js";
import { program } from "commander";
import { getPublicKey, signData } from "./vault";

const KEY_NAME = "guardian-1";

program
  .requiredOption("--to <address>", "Recipient Solana address")
  .requiredOption("--amount <sol>", "Amount of SOL to transfer")
  .option("--rpc <url>", "Solana RPC URL", clusterApiUrl("devnet"))
  .parse();

const opts = program.opts();

async function main() {
  const connection = new Connection(opts.rpc, "confirmed");

  // 1. Get public key from Vault (never see the private key)
  const pubkeyBytes = await getPublicKey(KEY_NAME);
  const fromPubkey = new PublicKey(pubkeyBytes);
  console.log(`From (Vault-derived): ${fromPubkey.toBase58()}`);

  // 2. Check balance
  const balance = await connection.getBalance(fromPubkey);
  const lamportsToSend = Math.round(parseFloat(opts.amount) * LAMPORTS_PER_SOL);
  console.log(`Balance: ${balance / LAMPORTS_PER_SOL} SOL`);
  console.log(`Sending: ${opts.amount} SOL to ${opts.to}`);

  if (balance < lamportsToSend + 5000) {
    console.error(
      `Insufficient balance. Fund this address on devnet:\n` +
        `  solana airdrop 1 ${fromPubkey.toBase58()} --url devnet`
    );
    process.exit(1);
  }

  // 3. Build transfer transaction
  const toPubkey = new PublicKey(opts.to);
  const tx = new Transaction().add(
    SystemProgram.transfer({
      fromPubkey,
      toPubkey,
      lamports: lamportsToSend,
    })
  );

  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;
  tx.feePayer = fromPubkey;

  // 4. Serialize the message (what gets signed)
  const message = tx.serializeMessage();

  // 5. Sign via Vault
  console.log("Signing via Vault transit engine...");
  const signature = await signData(KEY_NAME, message);

  // 6. Attach the signature
  tx.addSignature(fromPubkey, signature);

  // 7. Verify the signature is valid before sending
  if (!tx.verifySignatures()) {
    throw new Error("Signature verification failed — the Vault signature does not match the transaction message");
  }

  // 8. Submit
  const txSig = await connection.sendRawTransaction(tx.serialize());
  console.log(`\nTransaction submitted!`);
  console.log(`Signature: ${txSig}`);
  console.log(`Explorer:  https://explorer.solana.com/tx/${txSig}?cluster=devnet`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

**Step 2: Commit**

```bash
git add src/sign-transfer.ts
git commit -m "add CLI transfer script with vault-backed signing"
```

---

### Task 7: Systemd Reference Template

**Files:**
- Create: `systemd/guardian.service`

**Step 1: Write guardian.service**

```ini
# Reference template — not used in the Docker demo.
# Shows how to inject the Vault token via systemd in production.

[Unit]
Description=Guardian Signing Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=guardian
Group=guardian
WorkingDirectory=/opt/guardian

# Token injected as env var — not in a .env file.
# Option A: Direct environment variable (set by provisioning tooling)
Environment="VAULT_ADDR=https://vault.internal:8200"

# Option B: Credential from systemd LoadCredential (systemd 250+)
# LoadCredential=vault-token:/run/secrets/guardian-vault-token
# Environment="VAULT_TOKEN=%d/vault-token"

# Option C: EnvironmentFile owned by root, mode 0600
EnvironmentFile=/etc/guardian/token.env

ExecStart=/usr/bin/node /opt/guardian/dist/sign-transfer.js
Restart=on-failure
RestartSec=5

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

**Step 2: Commit**

```bash
git add systemd/guardian.service
git commit -m "add systemd reference template for production token injection"
```

---

### Task 8: README

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

```markdown
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
2. The CLI fetches the public key from Vault → derives the Solana address
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
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "add README with quickstart and architecture docs"
```

---

### Task 9: End-to-End Manual Test

**Step 1: Start Vault**

```bash
docker compose up -d
docker compose logs -f bootstrap
```

Wait for bootstrap to print the service token and Solana address.

**Step 2: Install deps and check the derived address**

```bash
yarn install
VAULT_TOKEN=<token> npx ts-node src/sign-transfer.ts --to 11111111111111111111111111111111 --amount 0.001
```

This should fail with "Insufficient balance" and print the Vault-derived Solana address.

**Step 3: Fund on devnet**

```bash
solana airdrop 1 <VAULT_DERIVED_ADDRESS> --url devnet
```

**Step 4: Execute a real transfer**

```bash
VAULT_TOKEN=<token> npx ts-node src/sign-transfer.ts --to <ANY_DEVNET_ADDRESS> --amount 0.01
```

Expected: Transaction submitted, explorer URL printed, verifiable on Solana Explorer.

**Step 5: Clean up**

```bash
docker compose down
```
