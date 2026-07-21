import { mkdirSync, writeFileSync } from "fs";
import { ethers } from "hardhat";

const EPBM_ABI = [
  "event ForkIntentRegistered(uint256 indexed mandateId, address indexed voter, uint256 weight)",
  "event MandateForked(uint256 indexed mandateId, uint256 forkWeight, uint256 thresholdWeight)",
  "function getMandate(uint256 mandateId) view returns ((uint256 id,address proposer,bytes32 descriptionHash,bytes32 scope,address[] targets,uint256[] values,bytes[] calldatas,uint256 bondAmount,uint256 snapshotBlock,uint256 totalEligibleWeight,uint256 votingDeadline,uint256 executionDeadline,uint8 state,uint256 yesWeight,uint256 noWeight,uint256 abstainWeight,uint256 voteEntropy))",
  "function forkIdByMandate(uint256 mandateId) view returns (uint256)",
  "function forkIntentWeight(uint256 mandateId) view returns (uint256)",
  "function governance() view returns (address)",
  "function pendingGovernance() view returns (address)",
  "function forkRegistry() view returns (address)"
];

const FORK_REGISTRY_ABI = [
  "function getFork(uint256 forkId) view returns ((uint256 forkId,uint256 mandateId,address proposer,address branchOwner,bytes32 scope,address token,address personhoodRegistry,address sourceGovernance,address governance,address branchGovernor,address branchToken,address branchEpbm,uint256 treasuryBalance,uint256 supportWeight,uint256 thresholdWeight,uint256 createdAt,uint256 finalizedAt,uint256 resolvedAt,uint256 supersededBy,uint8 lifecycleState,bool active))"
];

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(name);
  if (idx === -1 || idx + 1 >= process.argv.length) return undefined;
  return process.argv[idx + 1];
}

async function main() {
  const epbmAddress = parseArg("--epbm") || process.env.EPBM_ADDRESS;
  const mandateIdRaw = parseArg("--mandate-id") || process.env.MANDATE_ID;

  if (!epbmAddress || !ethers.isAddress(epbmAddress)) {
    throw new Error("Provide --epbm <address> or EPBM_ADDRESS");
  }
  if (!mandateIdRaw) throw new Error("Provide --mandate-id <id> or MANDATE_ID");

  const mandateId = BigInt(mandateIdRaw);
  const epbm = new ethers.Contract(epbmAddress, EPBM_ABI, ethers.provider);

  const mandate = await epbm.getMandate(mandateId);
  const forkId = await epbm.forkIdByMandate(mandateId);
  const forkIntentWeight = await epbm.forkIntentWeight(mandateId);
  const governance = await epbm.governance();
  const pendingGovernance = await epbm.pendingGovernance();
  const forkRegistryAddress = await epbm.forkRegistry();

  const intentEvents = await epbm.queryFilter(
    epbm.filters.ForkIntentRegistered(mandateId, null),
    0,
    "latest"
  );
  const forkedEvents = await epbm.queryFilter(
    epbm.filters.MandateForked(mandateId),
    0,
    "latest"
  );

  const forkSupporters = intentEvents.map((evt) => ({
    voter: String(evt.args?.voter),
    weight: String(evt.args?.weight),
    txHash: evt.transactionHash,
    blockNumber: evt.blockNumber
  }));

  let forkDetails: Record<string, unknown> | null = null;
  if (forkId > 0n && forkRegistryAddress !== ethers.ZeroAddress) {
    const registry = new ethers.Contract(forkRegistryAddress, FORK_REGISTRY_ABI, ethers.provider);
    const fork = await registry.getFork(forkId);
    forkDetails = {
      forkId: String(fork.forkId),
      mandateId: String(fork.mandateId),
      branchOwner: String(fork.branchOwner),
      branchGovernor: String(fork.branchGovernor),
      branchToken: String(fork.branchToken),
      supportWeight: String(fork.supportWeight),
      thresholdWeight: String(fork.thresholdWeight),
      lifecycleState: Number(fork.lifecycleState),
      active: Boolean(fork.active),
      createdAt: String(fork.createdAt),
      finalizedAt: String(fork.finalizedAt),
      resolvedAt: String(fork.resolvedAt),
      supersededBy: String(fork.supersededBy)
    };
  }

  const report = {
    generatedAt: new Date().toISOString(),
    epbm: epbmAddress,
    mandateId: mandateId.toString(),
    mandate: {
      id: String(mandate.id),
      proposer: String(mandate.proposer),
      scope: String(mandate.scope),
      state: Number(mandate.state),
      totalEligibleWeight: String(mandate.totalEligibleWeight),
      yesWeight: String(mandate.yesWeight),
      noWeight: String(mandate.noWeight),
      abstainWeight: String(mandate.abstainWeight),
      voteEntropy: String(mandate.voteEntropy),
      votingDeadline: String(mandate.votingDeadline),
      executionDeadline: String(mandate.executionDeadline)
    },
    forkSummary: {
      forkId: String(forkId),
      forkIntentWeight: String(forkIntentWeight),
      forkedEventCount: forkedEvents.length,
      forkedEvents: forkedEvents.map((evt) => ({
        txHash: evt.transactionHash,
        blockNumber: evt.blockNumber,
        forkWeight: String(evt.args?.forkWeight),
        thresholdWeight: String(evt.args?.thresholdWeight)
      }))
    },
    governanceState: {
      governance,
      pendingGovernance,
      forkRegistryAddress
    },
    supporters: forkSupporters,
    forkDetails
  };

  const outDir = `analysis/fork-legitimacy`;
  mkdirSync(outDir, { recursive: true });
  const jsonPath = `${outDir}/mandate-${mandateId.toString()}.json`;
  const mdPath = `${outDir}/mandate-${mandateId.toString()}.md`;

  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");

  const md = [
    `# Fork Legitimacy Report: Mandate ${mandateId.toString()}`,
    "",
    `- Generated at: ${report.generatedAt}`,
    `- EPBM: ${epbmAddress}`,
    `- Fork registry: ${forkRegistryAddress}`,
    `- Fork ID: ${report.forkSummary.forkId}`,
    "",
    "## Objective Onchain State",
    `- Mandate state enum: ${report.mandate.state}`,
    `- Eligible weight: ${report.mandate.totalEligibleWeight}`,
    `- NO weight: ${report.mandate.noWeight}`,
    `- Fork intent weight: ${report.forkSummary.forkIntentWeight}`,
    `- Forked event count: ${report.forkSummary.forkedEventCount}`,
    "",
    "## Supporter Intents",
    ...report.supporters.map((s) => `- ${s.voter} weight=${s.weight} block=${s.blockNumber}`),
    "",
    "## Governance State",
    `- governance: ${report.governanceState.governance}`,
    `- pendingGovernance: ${report.governanceState.pendingGovernance}`,
    ""
  ].join("\n");

  writeFileSync(mdPath, `${md}\n`, "utf8");
  console.log(`Wrote fork legitimacy report: ${jsonPath}`);
  console.log(`Wrote fork legitimacy summary: ${mdPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
