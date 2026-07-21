import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import type { EPBM, PersonhoodRegistry, GovernanceToken, MockTarget } from "../typechain-types";

const WAD = 10n ** 18n;
const DAY = 86_400n;
const WEEK = 7n * DAY;

function descHash(s: string) {
  return ethers.keccak256(ethers.toUtf8Bytes(s));
}

function scopeId(s: string) {
  return ethers.keccak256(ethers.toUtf8Bytes(s));
}

async function deployFixture() {
  const [owner, alice, bob, charlie] = await ethers.getSigners();

  const Token = await ethers.getContractFactory("GovernanceToken");
  const token = (await Token.deploy("EPBM Governance Token", "EPBM", owner.address)) as unknown as GovernanceToken;

  const Registry = await ethers.getContractFactory("PersonhoodRegistry");
  const registry = (await Registry.deploy(owner.address)) as unknown as PersonhoodRegistry;

  const EPBMFactory = await ethers.getContractFactory("EPBM");
  const epbm = (await EPBMFactory.deploy(
    token.target,
    registry.target,
    ethers.ZeroAddress,
    ethers.parseEther("0.1"),
    2n * WAD,
    1000n,
    2000n,
    5000n,
    1000n,
    2000n,
    1000n,
    WEEK,
    2n * DAY,
    WAD,
  )) as unknown as EPBM;

  const Target = await ethers.getContractFactory("MockTarget");
  const target = (await Target.deploy()) as unknown as MockTarget;

  await token.mint(alice.address, ethers.parseEther("600"));
  await token.mint(bob.address, ethers.parseEther("300"));
  await token.mint(charlie.address, ethers.parseEther("100"));

  await registry.setScore(alice.address, 50);
  await epbm.setScopeTarget(scopeId("treasury"), target.target as string, true);

  return { epbm, token, target, owner, alice, bob, charlie };
}

async function proposeSimple(epbm: EPBM, target: MockTarget, proposer: any, value: bigint, suffix: string) {
  const calldata = target.interface.encodeFunctionData("setValue", [42n]);
  await epbm.connect(proposer).propose(
    descHash(`Invariant Proposal ${suffix}`),
    scopeId("treasury"),
    [target.target as string],
    [0n],
    [calldata],
    { value },
  );
}

async function fastForwardPastVoting(epbm: EPBM, mandateId: bigint) {
  const m = await epbm.getMandate(mandateId);
  await time.increaseTo(Number(m.votingDeadline) + 1);
}

async function fastForwardPastExecution(epbm: EPBM, mandateId: bigint) {
  const m = await epbm.getMandate(mandateId);
  await time.increaseTo(Number(m.executionDeadline) + 1);
}

describe("EPBM invariants (fuzz-like)", function () {
  it("conserves bond accounting across randomized outcome sequences", async function () {
    const { epbm, target, alice, bob, charlie } = await deployFixture();

    let totalBondsPosted = 0n;
    const rounds = 12;

    for (let i = 0; i < rounds; i++) {
      const requiredBond = await epbm.computeRequiredBond();
      await proposeSimple(epbm, target, alice, requiredBond, `${i}`);

      const mandateId = BigInt(i + 1);
      const mandate = await epbm.getMandate(mandateId);
      totalBondsPosted += mandate.bondAmount;

      const mode = i % 4;
      if (mode === 0) {
        await epbm.connect(alice).castVote(mandateId, 0);
        await epbm.connect(bob).castVote(mandateId, 0);
        await fastForwardPastVoting(epbm, mandateId);
        await epbm.evaluate(mandateId);
        await epbm.connect(alice).execute(mandateId, { value: 0n });
      } else if (mode === 1) {
        await fastForwardPastVoting(epbm, mandateId);
        await epbm.evaluate(mandateId);
      } else if (mode === 2) {
        await epbm.connect(bob).castVote(mandateId, 1);
        await fastForwardPastVoting(epbm, mandateId);
        await epbm.evaluate(mandateId);
      } else {
        await epbm.connect(alice).castVote(mandateId, 0);
        await epbm.connect(bob).castVote(mandateId, 0);
        await fastForwardPastVoting(epbm, mandateId);
        await epbm.evaluate(mandateId);
        await fastForwardPastExecution(epbm, mandateId);
        await epbm.connect(charlie).claimExpiredBond(mandateId);
      }

      const contractBalance = await ethers.provider.getBalance(epbm.target as string);
      const claimable = await epbm.claimableBonds(alice.address);
      const slashed = await epbm.slashedBondPool();

      expect(contractBalance).to.equal(claimable + slashed);
      expect(totalBondsPosted).to.equal(claimable + slashed);
    }
  });

  it("prevents double bond claims under repeated claim attempts", async function () {
    const { epbm, target, alice } = await deployFixture();

    const requiredBond = await epbm.computeRequiredBond();
    await proposeSimple(epbm, target, alice, requiredBond, "double-claim");

    await fastForwardPastVoting(epbm, 1n);
    await epbm.evaluate(1n);

    const queued = await epbm.claimableBonds(alice.address);
    expect(queued).to.be.gt(0n);

    await epbm.connect(alice).claimBond();
    expect(await epbm.claimableBonds(alice.address)).to.equal(0n);

    await expect(epbm.connect(alice).claimBond()).to.be.revertedWith("Nothing to claim");
  });

  it("enforces monotonic governance transfer state transitions", async function () {
    const { epbm, owner, bob, charlie } = await deployFixture();

    await epbm.connect(owner).setGovernanceTransferDelay(DAY);

    await epbm.connect(owner).initiateGovernanceTransfer(bob.address);
    expect(await epbm.pendingGovernance()).to.equal(bob.address);
    expect(await epbm.pendingGovernanceNonce()).to.equal(1n);
    expect(await epbm.governanceTransferNonce()).to.equal(1n);

    await expect(
      epbm.connect(owner).initiateGovernanceTransfer(charlie.address),
    ).to.be.revertedWithCustomError(epbm, "GovernanceTransferPending");

    await expect(epbm.connect(bob).acceptGovernanceTransfer())
      .to.be.revertedWithCustomError(epbm, "GovernanceTransferTimelockActive");

    await time.increase(Number(DAY) + 1);
    await epbm.connect(bob).acceptGovernanceTransfer();

    expect(await epbm.governance()).to.equal(bob.address);
    expect(await epbm.pendingGovernance()).to.equal(ethers.ZeroAddress);
    expect(await epbm.pendingGovernanceNonce()).to.equal(0n);

    await expect(epbm.connect(owner).setGovernanceTransferDelay(0n))
      .to.be.revertedWithCustomError(epbm, "NotGovernance");

    await epbm.connect(bob).initiateGovernanceTransfer(charlie.address);
    expect(await epbm.pendingGovernance()).to.equal(charlie.address);
    expect(await epbm.pendingGovernanceNonce()).to.equal(2n);
    expect(await epbm.governanceTransferNonce()).to.equal(2n);
  });
});
