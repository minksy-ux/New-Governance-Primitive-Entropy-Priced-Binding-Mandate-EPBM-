import { ethers } from "hardhat";

const WAD = 10n ** 18n;
const DAY  = 86_400n;
const WEEK = 7n * DAY;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance: ", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

  // ── 1. PersonhoodRegistry ────────────────────────────────────────────────
  const Registry = await ethers.getContractFactory("PersonhoodRegistry");
  const registry = await Registry.deploy(deployer.address);
  await registry.waitForDeployment();
  console.log("PersonhoodRegistry:", await registry.getAddress());

  // ── 2. Governance token (mock — replace with real ERC20Votes in production) ──
  const Token = await ethers.getContractFactory("MockVotes");
  const token = await Token.deploy();
  await token.waitForDeployment();
  console.log("MockVotes token:   ", await token.getAddress());

  // ── 3. EPBM core contract ────────────────────────────────────────────────
  //
  // Parameter choices (conservative mainnet defaults):
  //
  //   baseBond              = 1 ETH
  //     → minimum skin-in-the-game for any proposal
  //
  //   bondEntropyFactor     = 3 WAD
  //     → at max entropy, bond rises to 4 ETH
  //
  //   baseQuorumBPS         = 1000  (10%)
  //     → at least 10% of token supply must vote
  //
  //   quorumEntropyFactor   = 3000  (+30% BPS at max entropy)
  //     → contested votes require 40% quorum
  //
  //   passageThresholdBPS   = 5000  (50%)
  //     → simple majority at low entropy
  //
  //   passageEntropyFactor  = 2000  (+20% BPS at max entropy)
  //     → contested votes require 70% supermajority
  //
  //   vetoThresholdBPS      = 1500  (15%)
  //     → 15% hard NO triggers minority veto
  //
  //   votingPeriod          = 7 days
  //   executionWindow       = 3 days
  //
  //   personhoodBoostFactor = 0.5 WAD
  //     → fully verified human gets up to +50% vote weight

  const EPBM = await ethers.getContractFactory("EPBM");
  const epbm = await EPBM.deploy(
    await token.getAddress(),
    await registry.getAddress(),
    ethers.parseEther("1"),      // baseBond
    3n * WAD,                    // bondEntropyFactor
    1000n,                       // baseQuorumBPS
    3000n,                       // quorumEntropyFactor
    5000n,                       // passageThresholdBPS
    2000n,                       // passageEntropyFactor
    1500n,                       // vetoThresholdBPS
    WEEK,                        // votingPeriod
    3n * DAY,                    // executionWindow
    WAD / 2n,                    // personhoodBoostFactor (0.5)
  );
  await epbm.waitForDeployment();
  console.log("EPBM:              ", await epbm.getAddress());

  console.log("\n✓ Deployment complete.");
  console.log("  → Transfer PersonhoodRegistry admin to a multisig before mainnet launch.");
  console.log("  → Replace MockVotes with a real ERC20Votes token.");
  console.log("  → Transfer EPBM governance to address(epbm) to make the protocol self-governing.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
