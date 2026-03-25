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
