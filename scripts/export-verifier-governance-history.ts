import { mkdirSync, writeFileSync } from "fs";
import { ethers } from "hardhat";

const ABI = [
  "event AdminTransferInitiated(address indexed newAdmin)",
  "event AdminTransferAccepted(address indexed newAdmin)",
  "event VerifierUpdated(address indexed verifier)",
  "event VerifierStatusUpdated(address indexed verifier, bool enabled)",
  "event VerifierChangeQueued(address indexed verifier, bool enabled, uint256 executeAfter)",
  "event ManualScoreWritesDisabled()",
  "event DecentralizationFinalized(address indexed finalAdmin)",
  "function admin() view returns (address)",
  "function pendingAdmin() view returns (address)",
  "function activeVerifierCount() view returns (uint256)",
  "function manualScoreWritesDisabled() view returns (bool)",
  "function decentralizationFinalized() view returns (bool)",
  "function verifierChangeDelay() view returns (uint256)"
];

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(name);
  if (idx === -1 || idx + 1 >= process.argv.length) return undefined;
  return process.argv[idx + 1];
}

async function main() {
  const registryAddress = parseArg("--registry") || process.env.REGISTRY_ADDRESS;
  if (!registryAddress || !ethers.isAddress(registryAddress)) {
    throw new Error("Provide --registry <address> or REGISTRY_ADDRESS");
  }

  const fromBlock = Number(parseArg("--from-block") || process.env.FROM_BLOCK || 0);
  const toBlock = Number(parseArg("--to-block") || process.env.TO_BLOCK || (await ethers.provider.getBlockNumber()));
  const outFile = parseArg("--out") || process.env.OUT_FILE || "analysis/verifier-governance-history.json";

  const registry = new ethers.Contract(registryAddress, ABI, ethers.provider);

  const eventNames = [
    "AdminTransferInitiated",
    "AdminTransferAccepted",
    "VerifierUpdated",
    "VerifierStatusUpdated",
    "VerifierChangeQueued",
    "ManualScoreWritesDisabled",
    "DecentralizationFinalized"
  ] as const;

  const logs: Array<{
    event: string;
    blockNumber: number;
    txHash: string;
    logIndex: number;
    args: Record<string, string | number | boolean>;
  }> = [];

  for (const eventName of eventNames) {
    const events = await registry.queryFilter(registry.filters[eventName](), fromBlock, toBlock);
    for (const evt of events) {
      const args: Record<string, string | number | boolean> = {};
      if (evt.args) {
        for (const key of Object.keys(evt.args)) {
          if (/^\d+$/.test(key)) continue;
          const value = evt.args[key];
          if (typeof value === "bigint") args[key] = value.toString();
          else if (typeof value === "boolean") args[key] = value;
          else args[key] = String(value);
        }
      }

      logs.push({
        event: eventName,
        blockNumber: evt.blockNumber,
        txHash: evt.transactionHash,
        logIndex: evt.index,
        args
      });
    }
  }

  logs.sort((a, b) => (a.blockNumber - b.blockNumber) || (a.logIndex - b.logIndex));

  const summary = {
    registry: registryAddress,
    fromBlock,
    toBlock,
    admin: await registry.admin(),
    pendingAdmin: await registry.pendingAdmin(),
    activeVerifierCount: (await registry.activeVerifierCount()).toString(),
    manualScoreWritesDisabled: await registry.manualScoreWritesDisabled(),
    decentralizationFinalized: await registry.decentralizationFinalized(),
    verifierChangeDelay: (await registry.verifierChangeDelay()).toString(),
    eventCount: logs.length
  };

  const payload = {
    generatedAt: new Date().toISOString(),
    summary,
    logs
  };

  const outDir = outFile.includes("/") ? outFile.slice(0, outFile.lastIndexOf("/")) : ".";
  mkdirSync(outDir, { recursive: true });
  writeFileSync(outFile, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  console.log(`Wrote verifier governance history: ${outFile}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
