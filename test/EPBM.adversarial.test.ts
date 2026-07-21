import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import type {
  EPBM,
  PersonhoodRegistry,
  GovernanceToken,
  MockTarget,
  ForkRegistry,
} from "../typechain-types";

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

  const ForkRegistryFactory = await ethers.getContractFactory("ForkRegistry");
  const forkRegistry = (await ForkRegistryFactory.deploy(epbm.target)) as unknown as ForkRegistry;
  await epbm.setForkRegistry(forkRegistry.target);

  const Target = await ethers.getContractFactory("MockTarget");
  const target = (await Target.deploy()) as unknown as MockTarget;

  await token.mint(alice.address, ethers.parseEther("600"));
  await token.mint(bob.address, ethers.parseEther("300"));
  await token.mint(charlie.address, ethers.parseEther("100"));

  await registry.setScore(alice.address, 50);
  await epbm.setScopeTarget(scopeId("treasury"), target.target as string, true);

  return { epbm, registry, target, owner, alice, bob, charlie };
}

async function proposeSimple(epbm: EPBM, target: MockTarget, proposer: any, suffix: string) {
  const calldata = target.interface.encodeFunctionData("setValue", [42n]);
  const bond = await epbm.computeRequiredBond();
  await epbm.connect(proposer).propose(
    descHash(`Adversarial Proposal ${suffix}`),
    scopeId("treasury"),
    [target.target as string],
    [0n],
    [calldata],
    { value: bond },
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

describe("EPBM adversarial and differential tests", function () {
  it("keeps previewEvaluation and evaluate() outcomes aligned across diverse voting patterns", async function () {
    const { epbm, target, alice, bob, charlie } = await deployFixture();

    const scenarios = [
      {
        suffix: "yes-only-pass",
        votes: [
          { voter: alice, choice: 0 as const },
          { voter: charlie, choice: 0 as const },
        ],
      },
      {
        suffix: "vetoed-no",
        votes: [
          { voter: bob, choice: 1 as const },
        ],
      },
      {
        suffix: "abstain-defeat",
        votes: [
          { voter: alice, choice: 2 as const },
        ],
      },
      {
        suffix: "contested-pass",
        votes: [
          { voter: alice, choice: 0 as const },
          { voter: charlie, choice: 1 as const },
        ],
      },
    ];

    for (let i = 0; i < scenarios.length; i++) {
      const mandateId = BigInt(i + 1);
      const scenario = scenarios[i];
      await proposeSimple(epbm, target, alice, scenario.suffix);

      for (const vote of scenario.votes) {
        await epbm.connect(vote.voter).castVote(mandateId, vote.choice);
      }

      const preview = await epbm.previewEvaluation(mandateId);
      await fastForwardPastVoting(epbm, mandateId);
      const tx = await epbm.evaluate(mandateId);
      await tx.wait();

      const m = await epbm.getMandate(mandateId);
      expect(m.state).to.equal(preview.predictedOutcome);
    }
  });

  it("enforces fork-intent timing boundaries and activates exactly at threshold", async function () {
    const { epbm, target, alice, bob, charlie } = await deployFixture();

    await proposeSimple(epbm, target, alice, "fork-boundary");

    await epbm.connect(alice).castVote(1n, 0);
    await epbm.connect(charlie).castVote(1n, 1);

    await expect(epbm.connect(charlie).registerForkIntent(1n))
      .to.be.revertedWithCustomError(epbm, "InvalidMandateState");

    await fastForwardPastVoting(epbm, 1n);
    await epbm.evaluate(1n);

    const before = await epbm.getMandate(1n);
    expect(before.state).to.equal(2n);

    const threshold = (before.totalEligibleWeight * 1000n) / 10_000n;
    const noVote = await epbm.getVote(1n, charlie.address);
    expect(noVote.weight).to.equal(threshold);

    await epbm.connect(charlie).registerForkIntent(1n);

    const after = await epbm.getMandate(1n);
    expect(after.state).to.equal(7n);
    expect(await epbm.forkIdByMandate(1n)).to.equal(1n);

    await proposeSimple(epbm, target, alice, "fork-deadline");
    await epbm.connect(alice).castVote(2n, 0);
    await epbm.connect(charlie).castVote(2n, 1);
    await fastForwardPastVoting(epbm, 2n);
    await epbm.evaluate(2n);
    await fastForwardPastExecution(epbm, 2n);

    await expect(epbm.connect(charlie).registerForkIntent(2n))
      .to.be.revertedWithCustomError(epbm, "ExecutionWindowExpired");

    await expect(epbm.connect(bob).registerForkIntent(2n))
      .to.be.revertedWithCustomError(epbm, "ExecutionWindowExpired");
  });

  it("keeps settlement paths available after protocol-surface freeze while blocking governance mutation", async function () {
    const { epbm, target, owner, alice, charlie } = await deployFixture();

    await epbm.connect(owner).setGovernanceTransferDelay(DAY);
    await epbm.connect(owner).finalizeProtocolSurface();

    await expect(epbm.connect(owner).setForkRegistry(ethers.ZeroAddress))
      .to.be.revertedWithCustomError(epbm, "ProtocolSurfaceFinalized");
    await expect(epbm.connect(owner).setScopeTarget(scopeId("treasury"), target.target as string, false))
      .to.be.revertedWithCustomError(epbm, "ProtocolSurfaceFinalized");

    await proposeSimple(epbm, target, alice, "freeze-and-settle");
    await epbm.connect(alice).castVote(1n, 0);
    await epbm.connect(charlie).castVote(1n, 1);

    await fastForwardPastVoting(epbm, 1n);
    await epbm.evaluate(1n);

    await epbm.connect(charlie).registerForkIntent(1n);

    const m = await epbm.getMandate(1n);
    expect(m.state).to.equal(7n);
  });

  it("keeps personhood attestation updates live after decentralization freeze", async function () {
    const { registry, owner, alice, bob } = await deployFixture();

    const chainId = (await ethers.provider.getNetwork()).chainId;

    const domain = {
      name: "EPBM Personhood Registry",
      version: "1",
      chainId,
      verifyingContract: registry.target as string,
    };

    const types = {
      PersonhoodScoreAttestation: [
        { name: "account", type: "address" },
        { name: "score", type: "uint256" },
        { name: "expiry", type: "uint256" },
        { name: "nonce", type: "uint256" },
      ],
    };

    await registry.connect(owner).queueVerifierStatusChange(alice.address, true);
    await time.increase(Number(DAY) + 1);
    await registry.connect(owner).setVerifierStatus(alice.address, true);

    await registry.connect(owner).disableManualScoreWrites();
    await registry.connect(owner).finalizeDecentralization();

    await expect(registry.connect(owner).setVerifierStatus(bob.address, true))
      .to.be.revertedWithCustomError(registry, "RegistryFrozen");

    const expiry = BigInt((await time.latest()) + 3600);
    const nonce = 1n;
    const value = {
      account: bob.address,
      score: 77n,
      expiry,
      nonce,
    };

    const digest = ethers.TypedDataEncoder.hash(domain, types, value);
    const signature = await alice.signMessage(ethers.getBytes(digest));

    await registry.setScoreByAttestation(bob.address, 77, expiry, nonce, signature);
    expect(await registry.scoreOf(bob.address)).to.equal(77n);
  });
});
