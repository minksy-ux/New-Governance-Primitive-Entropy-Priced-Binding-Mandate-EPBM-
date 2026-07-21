import { ethers } from "hardhat";

function parseRegistryAddress(): string {
  const argAddress = process.argv[2];
  const envAddress = process.env.REGISTRY_ADDRESS;
  const address = argAddress || envAddress;

  if (!address) {
    throw new Error(
      "Missing registry address. Provide as first arg or set REGISTRY_ADDRESS. Example: hardhat run scripts/check-finalization-readiness.ts --network localhost -- 0x...",
    );
  }

  if (!ethers.isAddress(address)) {
    throw new Error(`Invalid registry address: ${address}`);
  }

  return address;
}

async function main() {
  const registryAddress = parseRegistryAddress();
  const registry = await ethers.getContractAt("PersonhoodRegistry", registryAddress);

  const status = await registry.finalizationReadiness();

  const ready = status.ready;
  const manualWritesDisabled = status.manualWritesDisabled;
  const hasNoPendingAdmin = status.hasNoPendingAdmin;
  const verifierCount = status.verifierCount;
  const enoughVerifiers = status.enoughVerifiers;
  const minimum = await registry.MIN_VERIFIERS_FOR_FINALIZATION();
  const frozen = await registry.decentralizationFinalized();

  console.log("PersonhoodRegistry finalization preflight");
  console.log("----------------------------------------");
  console.log(`registry:                 ${registryAddress}`);
  console.log(`decentralizationFinalized:${frozen}`);
  console.log(`ready:                    ${ready}`);
  console.log(`manualWritesDisabled:     ${manualWritesDisabled}`);
  console.log(`hasNoPendingAdmin:        ${hasNoPendingAdmin}`);
  console.log(`verifierCount:            ${verifierCount}`);
  console.log(`minimumVerifiersRequired: ${minimum}`);
  console.log(`enoughVerifiers:          ${enoughVerifiers}`);

  if (!ready) {
    const blockers: string[] = [];
    if (!manualWritesDisabled) blockers.push("manual score writes not disabled");
    if (!hasNoPendingAdmin) blockers.push("pending admin transfer exists");
    if (!enoughVerifiers) blockers.push("insufficient active verifiers");

    console.error("\nPreflight status: NOT READY");
    console.error(`Blockers: ${blockers.join("; ")}`);
    process.exitCode = 1;
    return;
  }

  if (frozen) {
    console.log("\nPreflight status: ALREADY FINALIZED");
    return;
  }

  console.log("\nPreflight status: READY TO FINALIZE");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
