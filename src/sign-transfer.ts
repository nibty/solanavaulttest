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
    throw new Error(
      "Signature verification failed — the Vault signature does not match the transaction message"
    );
  }

  // 8. Submit
  const txSig = await connection.sendRawTransaction(tx.serialize());
  console.log(`\nTransaction submitted!`);
  console.log(`Signature: ${txSig}`);
  console.log(
    `Explorer:  https://explorer.solana.com/tx/${txSig}?cluster=devnet`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
