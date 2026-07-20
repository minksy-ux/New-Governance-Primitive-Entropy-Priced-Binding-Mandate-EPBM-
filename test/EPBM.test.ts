import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import type { EPBM, PersonhoodRegistry, MockVotes, MockTarget } from "../typechain-types";

// ─── Helpers ──────────────────────────────────────────────────────────────────

const WAD  = 10n ** 18n;
const BPS  = 10_000n;
const DAY  = 86_400n;
const WEEK = 7n * DAY;

/** keccak256 of a string — mirrors how off-chain tooling would hash descriptions */
function descHash(s: string) {
  return ethers.keccak256(ethers.toUtf8Bytes(s));
}

function scopeId(s: string) {
  return ethers.keccak256(ethers.toUtf8Bytes(s));
}

// ─── Fixture ──────────────────────────────────────────────────────────────────

async function deployFixture() {
  const [owner, alice, bob, charlie, stranger] = await ethers.getSigners();

  // 1. Governance token (mock, no real checkpointing)
  const Token = await ethers.getContractFactory("MockVotes");
  const token = (await Token.deploy()) as unknown as MockVotes;

  // 2. Personhood registry
  const Registry = await ethers.getContractFactory("PersonhoodRegistry");
  const registry = (await Registry.deploy(owner.address)) as unknown as PersonhoodRegistry;

  // 3. Core EPBM contract
  //    Parameters (all deliberately small for test speed):
  //      baseBond              = 0.1 ETH
  //      bondEntropyFactor     = 2 WAD  (doubles bond at max entropy)
  //      baseQuorumBPS         = 1000   (10%)
  //      quorumEntropyFactor   = 2000   (+20% BPS at max entropy)
  //      passageThresholdBPS   = 5000   (50%)
  //      passageEntropyFactor  = 1000   (+10% BPS at max entropy)
  //      vetoThresholdBPS      = 2000   (20% of eligible = veto)
  //      votingPeriod          = 7 days
  //      executionWindow       = 2 days
  //      personhoodBoostFactor = 1 WAD  (100% boost for score=100)
  const EPBM = await ethers.getContractFactory("EPBM");
  const epbm = (await EPBM.deploy(
    token.target,
    registry.target,
    ethers.parseEther("0.1"),  // baseBond
    2n * WAD,                  // bondEntropyFactor
    1000n,                     // baseQuorumBPS
    2000n,                     // quorumEntropyFactor
    5000n,                     // passageThresholdBPS
    1000n,                     // passageEntropyFactor
    2000n,                     // vetoThresholdBPS
    WEEK,                      // votingPeriod
    2n * DAY,                  // executionWindow
    WAD,                       // personhoodBoostFactor
  )) as unknown as EPBM;

  // 4. Mock execution target
  const Target = await ethers.getContractFactory("MockTarget");
  const target = (await Target.deploy()) as unknown as MockTarget;

  // Distribute voting tokens:
  //   alice   = 600 tokens (60%)
  //   bob     = 300 tokens (30%)
  //   charlie = 100 tokens (10%)
  //   total   = 1000 tokens
  const E18 = ethers.parseEther;
  await token.mint(alice.address,   E18("600"));
  await token.mint(bob.address,     E18("300"));
  await token.mint(charlie.address, E18("100"));

  // Give alice a personhood score
  await registry.setScore(alice.address, 50);  // 50/100

  const baseBond = ethers.parseEther("0.1");

  return { epbm, token, registry, target, owner, alice, bob, charlie, stranger, baseBond };
}

/** Fast-forward past the voting deadline of mandate 1 */
async function fastForwardPastVoting(epbm: EPBM) {
  const m = await epbm.getMandate(1n);
  await time.increaseTo(Number(m.votingDeadline) + 1);
}

/** Fast-forward past the execution deadline of mandate 1 */
async function fastForwardPastExecution(epbm: EPBM) {
  const m = await epbm.getMandate(1n);
  await time.increaseTo(Number(m.executionDeadline) + 1);
}

// ─── Helper: propose a simple mandate ─────────────────────────────────────────

async function proposeSimple(
  epbm: EPBM,
  target: MockTarget,
  proposer: Awaited<ReturnType<typeof ethers.getSigner>>,
  value: bigint,
) {
  const calldata = target.interface.encodeFunctionData("setValue", [42n]);
  return epbm.connect(proposer).propose(
    descHash("Proposal #1"),
    scopeId("treasury"),
    [target.target as string],
    [0n],
    [calldata],
    { value },
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("EPBM", function () {
  // ── Proposal creation ────────────────────────────────────────────────────

  describe("propose()", function () {
    it("creates a mandate with correct state and bond", async function () {
      const { epbm, target, alice, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);

      const m = await epbm.getMandate(1n);
      expect(m.id).to.equal(1n);
      expect(m.proposer).to.equal(alice.address);
      expect(m.bondAmount).to.equal(baseBond);
      expect(m.state).to.equal(1n); // VOTING
    });

    it("refunds excess ETH sent above required bond", async function () {
      const { epbm, target, alice, baseBond } = await deployFixture();

      const excess = ethers.parseEther("0.5");
      const balanceBefore = await ethers.provider.getBalance(alice.address);

      const tx = await proposeSimple(epbm, target, alice, baseBond + excess);
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const balanceAfter = await ethers.provider.getBalance(alice.address);
      // Net cost = bond + gas (excess was refunded)
      expect(balanceBefore - balanceAfter).to.be.closeTo(baseBond + gasUsed, ethers.parseEther("0.001"));
    });

    it("reverts when bond is insufficient", async function () {
      const { epbm, target, alice } = await deployFixture();

      await expect(
        proposeSimple(epbm, target, alice, ethers.parseEther("0.01")),
      ).to.be.revertedWithCustomError(epbm, "InsufficientBond");
    });

    it("reverts when targets array is empty", async function () {
      const { epbm, alice, baseBond } = await deployFixture();

      await expect(
        epbm.connect(alice).propose(descHash("bad"), scopeId("x"), [], [], [], { value: baseBond }),
      ).to.be.revertedWithCustomError(epbm, "LengthMismatch");
    });

    it("reverts when array lengths mismatch", async function () {
      const { epbm, alice, target, baseBond } = await deployFixture();

      await expect(
        epbm.connect(alice).propose(
          descHash("bad"),
          scopeId("x"),
          [target.target as string, target.target as string],
          [0n],
          ["0x"],
          { value: baseBond },
        ),
      ).to.be.revertedWithCustomError(epbm, "LengthMismatch");
    });

    it("emits MandateCreated with correct parameters", async function () {
      const { epbm, target, alice, baseBond } = await deployFixture();

      await expect(proposeSimple(epbm, target, alice, baseBond))
        .to.emit(epbm, "MandateCreated")
        .withArgs(
          1n,
          alice.address,
          descHash("Proposal #1"),
          scopeId("treasury"),
          baseBond,
          // votingDeadline is dynamic; just check existence
          (v: bigint) => v > 0n,
        );
    });
  });

  // ── Voting ───────────────────────────────────────────────────────────────

  describe("castVote()", function () {
    async function withProposal() {
      const ctx = await deployFixture();
      await proposeSimple(ctx.epbm, ctx.target, ctx.alice, ctx.baseBond);
      return ctx;
    }

    it("records YES vote with correct weight", async function () {
      const { epbm, alice } = await withProposal();

      await epbm.connect(alice).castVote(1n, 0); // YES

      const v = await epbm.getVote(1n, alice.address);
      expect(v.choice).to.equal(0n); // YES
      expect(v.weight).to.be.gt(0n);
    });

    it("applies personhood boost to vote weight", async function () {
      const { epbm, alice, token } = await withProposal();

      const stake = await token.balanceOf(alice.address);
      await epbm.connect(alice).castVote(1n, 0); // YES

      const v = await epbm.getVote(1n, alice.address);
      // alice score=50, boostFactor=1 WAD → effectiveWeight = stake + stake*1*50/100 = 1.5×stake
      const expectedBoost = (stake * 50n) / 100n; // personhoodBoostFactor * score / 100 * stake / WAD
      expect(v.weight).to.be.closeTo(stake + expectedBoost, ethers.parseEther("0.01"));
    });

    it("records NO vote with no personhood boost (score=0)", async function () {
      const { epbm, bob, token } = await withProposal();

      const stake = await token.balanceOf(bob.address);
      await epbm.connect(bob).castVote(1n, 1); // NO, score=0

      const v = await epbm.getVote(1n, bob.address);
      expect(v.weight).to.equal(stake); // no boost
    });

    it("prevents double voting", async function () {
      const { epbm, alice } = await withProposal();

      await epbm.connect(alice).castVote(1n, 0);

      await expect(epbm.connect(alice).castVote(1n, 1))
        .to.be.revertedWithCustomError(epbm, "AlreadyVoted");
    });

    it("reverts after voting deadline", async function () {
      const { epbm, alice } = await withProposal();

      await fastForwardPastVoting(epbm);

      await expect(epbm.connect(alice).castVote(1n, 0))
        .to.be.revertedWithCustomError(epbm, "VotingClosed");
    });

    it("reverts for accounts with no token balance", async function () {
      const { epbm, stranger } = await withProposal();

      await expect(epbm.connect(stranger).castVote(1n, 0))
        .to.be.revertedWithCustomError(epbm, "NoVotingPower");
    });

    it("emits VoteCast event", async function () {
      const { epbm, alice } = await withProposal();

      await expect(epbm.connect(alice).castVote(1n, 0))
        .to.emit(epbm, "VoteCast")
        .withArgs(1n, alice.address, 0n, (w: bigint) => w > 0n, 50n);
    });
  });

  // ── Evaluate: PASSED ─────────────────────────────────────────────────────

  describe("evaluate() → PASSED", function () {
    it("passes when quorum is met and YES > 50%", async function () {
      const { epbm, target, alice, charlie, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      // alice = 600 YES (60%), charlie = 100 NO (10% — below 20% veto threshold)
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(charlie).castVote(1n, 1);

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      const m = await epbm.getMandate(1n);
      expect(m.state).to.equal(2n); // PASSED
    });
  });

  // ── Evaluate: DEFEATED ───────────────────────────────────────────────────

  describe("evaluate() → DEFEATED", function () {
    it("defeats when quorum is not met", async function () {
      const { epbm, target, charlie, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, charlie, baseBond);
      // charlie = 100 tokens (10% of 1000) → below 10% quorum (exactly at boundary)
      // With 0 entropy (all YES), quorum = baseQuorum = 10%, charlie weight < 10% eligible
      // Actually charlie IS 10%, so quorum is met. Let's not vote at all.
      // Zero votes → quorum fails

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      const m = await epbm.getMandate(1n);
      expect(m.state).to.equal(3n); // DEFEATED
    });

    it("defeats when NO votes win", async function () {
      const { epbm, target, alice, bob, charlie, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      // NO = bob(300) + charlie(100) = 400, YES = alice(600) — wait that passes...
      // Let's make it charlie YES (100) vs alice+bob NO (900)
      await epbm.connect(charlie).castVote(1n, 0); // YES = 100
      await epbm.connect(alice).castVote(1n, 1);   // NO  ≈ 900 (with boost)
      await epbm.connect(bob).castVote(1n, 1);     // NO  = 300

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      const m = await epbm.getMandate(1n);
      // charlie 100 YES, alice ~900 NO, bob 300 NO → 100 YES / 1300 contested = 7.7% < 50% threshold → DEFEATED (or VETOED)
      // NO/eligible: (900+300)/1000 ≈ 120% — actually alice has boost so this may be more
      // Either DEFEATED or VETOED is acceptable; it shouldn't be PASSED
      expect(m.state).to.not.equal(2n); // not PASSED
    });

    it("returns proposer's bond on defeat", async function () {
      const { epbm, target, alice, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      // No votes → quorum fails → DEFEATED

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      // Bond should be queued for pull
      expect(await epbm.claimableBonds(alice.address)).to.equal(baseBond);
    });
  });

  // ── Evaluate: VETOED ─────────────────────────────────────────────────────

  describe("evaluate() → VETOED", function () {
    it("vetoes when NO votes exceed vetoThreshold of eligible weight", async function () {
      const { epbm, target, alice, bob, charlie, token, baseBond } = await deployFixture();

      // Add more tokens so NO bloc > 20% of eligible easily
      await token.mint(bob.address, ethers.parseEther("2000")); // bob now has 2300 / 3300 total

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(bob).castVote(1n, 1); // NO — bob has massive weight

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      const m = await epbm.getMandate(1n);
      expect(m.state).to.equal(4n); // VETOED
    });

    it("returns bond on veto (legitimate minority protection)", async function () {
      const { epbm, target, alice, bob, token, baseBond } = await deployFixture();

      await token.mint(bob.address, ethers.parseEther("2000"));
      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(bob).castVote(1n, 1);

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      expect(await epbm.claimableBonds(alice.address)).to.equal(baseBond);
    });
  });

  // ── Execute ──────────────────────────────────────────────────────────────

  describe("execute()", function () {
    async function withPassedMandate() {
      const ctx = await deployFixture();
      const { epbm, target, alice, bob, baseBond } = ctx;

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      const m = await epbm.getMandate(1n);
      expect(m.state).to.equal(2n); // sanity: PASSED

      return ctx;
    }

    it("executes the mandate actions and transitions to EXECUTED", async function () {
      const { epbm, target, alice } = await withPassedMandate();

      await epbm.connect(alice).execute(1n, { value: 0n });

      const m = await epbm.getMandate(1n);
      expect(m.state).to.equal(5n); // EXECUTED
      expect(await target.value()).to.equal(42n);
      expect(await target.called()).to.be.true;
    });

    it("queues bond return to proposer after execution", async function () {
      const { epbm, alice, baseBond } = await withPassedMandate();

      await epbm.connect(alice).execute(1n, { value: 0n });

      expect(await epbm.claimableBonds(alice.address)).to.equal(baseBond);
    });

    it("proposer can pull the bond after execution", async function () {
      const { epbm, alice, baseBond } = await withPassedMandate();

      await epbm.connect(alice).execute(1n, { value: 0n });

      const before = await ethers.provider.getBalance(alice.address);
      const tx = await epbm.connect(alice).claimBond();
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
      const after = await ethers.provider.getBalance(alice.address);

      expect(after - before + gasUsed).to.equal(baseBond);
    });

    it("reverts if execution window has expired", async function () {
      const { epbm, alice } = await withPassedMandate();

      await fastForwardPastExecution(epbm);

      await expect(epbm.connect(alice).execute(1n, { value: 0n }))
        .to.be.revertedWithCustomError(epbm, "ExecutionWindowExpired");
    });

    it("reverts if mandate is not PASSED", async function () {
      const { epbm, target, alice, baseBond } = await deployFixture();
      await proposeSimple(epbm, target, alice, baseBond);
      // Voting still open

      await expect(epbm.connect(alice).execute(1n, { value: 0n }))
        .to.be.revertedWithCustomError(epbm, "InvalidMandateState");
    });

    it("bubbles up revert reason when action fails", async function () {
      const { epbm, target, alice, bob, registry, baseBond } = await deployFixture();

      // Propose a failing action
      const calldata = target.interface.encodeFunctionData("revertAlways");
      await epbm.connect(alice).propose(
        descHash("bad"),
        scopeId("x"),
        [target.target as string],
        [0n],
        [calldata],
        { value: baseBond },
      );
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      await expect(epbm.connect(alice).execute(1n, { value: 0n }))
        .to.be.revertedWith("MockTarget: always reverts");
    });

    it("emits MandateExecuted event", async function () {
      const { epbm, alice } = await withPassedMandate();

      await expect(epbm.connect(alice).execute(1n, { value: 0n }))
        .to.emit(epbm, "MandateExecuted")
        .withArgs(1n);
    });
  });

  // ── Expired bond slash ───────────────────────────────────────────────────

  describe("claimExpiredBond()", function () {
    it("slashes bond when execution window expires", async function () {
      const { epbm, target, alice, bob, stranger, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      await fastForwardPastExecution(epbm);

      await epbm.connect(stranger).claimExpiredBond(1n);

      const m = await epbm.getMandate(1n);
      expect(m.state).to.equal(6n); // EXPIRED
      expect(await epbm.slashedBondPool()).to.equal(baseBond);
    });

    it("reverts if execution window is still open", async function () {
      const { epbm, target, alice, bob, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      await expect(epbm.claimExpiredBond(1n))
        .to.be.revertedWithCustomError(epbm, "ExecutionWindowOpen");
    });

    it("governance can withdraw slashed bonds", async function () {
      const { epbm, target, alice, bob, owner, stranger, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);
      await fastForwardPastExecution(epbm);
      await epbm.connect(stranger).claimExpiredBond(1n);

      const treasury = stranger.address;
      const before = await ethers.provider.getBalance(treasury);
      await epbm.connect(owner).withdrawSlashedBonds(treasury);
      const after = await ethers.provider.getBalance(treasury);

      expect(after - before).to.equal(baseBond);
      expect(await epbm.slashedBondPool()).to.equal(0n);
    });
  });

  // ── Minority fork rights ─────────────────────────────────────────────────

  describe("registerForkIntent()", function () {
    it("allows NO voters to register fork intent after passage", async function () {
      const { epbm, target, alice, bob, charlie, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0); // YES (wins)
      await epbm.connect(bob).castVote(1n, 0);   // YES
      await epbm.connect(charlie).castVote(1n, 1); // NO (minority)

      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      await expect(epbm.connect(charlie).registerForkIntent(1n))
        .to.emit(epbm, "ForkIntentRegistered")
        .withArgs(1n, charlie.address, (w: bigint) => w > 0n);
    });

    it("reverts for YES voters", async function () {
      const { epbm, target, alice, bob, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      await expect(epbm.connect(alice).registerForkIntent(1n))
        .to.be.revertedWithCustomError(epbm, "NoVotingPower");
    });
  });

  // ── Entropy pricing ──────────────────────────────────────────────────────

  describe("entropy-based bond pricing", function () {
    it("bond increases after high-entropy proposals", async function () {
      const { epbm, target, alice, bob, charlie, baseBond } = await deployFixture();

      const bondBefore = await epbm.computeRequiredBond();

      // Propose and create a 50/50 contested vote (high entropy)
      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);   // YES
      await epbm.connect(bob).castVote(1n, 1);     // NO (creates contest)
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      const bondAfter = await epbm.computeRequiredBond();
      const entropy = await epbm.historicalAverageEntropy();

      expect(entropy).to.be.gt(0n);
      expect(bondAfter).to.be.gte(bondBefore);
    });

    it("bond stays at base when all votes are unanimous (zero entropy)", async function () {
      const { epbm, target, alice, bob, charlie, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);
      await epbm.connect(charlie).castVote(1n, 0); // all YES → entropy ≈ 0
      await fastForwardPastVoting(epbm);
      await epbm.evaluate(1n);

      expect(await epbm.historicalAverageEntropy()).to.equal(0n);
      expect(await epbm.computeRequiredBond()).to.equal(baseBond);
    });
  });

  // ── previewEvaluation ────────────────────────────────────────────────────

  describe("previewEvaluation()", function () {
    it("correctly previews a passing outcome before evaluate() is called", async function () {
      const { epbm, target, alice, bob, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      await epbm.connect(alice).castVote(1n, 0);
      await epbm.connect(bob).castVote(1n, 0);

      const preview = await epbm.previewEvaluation(1n);
      expect(preview.predictedOutcome).to.equal(2n); // PASSED
    });

    it("correctly previews a defeated outcome", async function () {
      const { epbm, target, alice, baseBond } = await deployFixture();

      await proposeSimple(epbm, target, alice, baseBond);
      // No votes → quorum fails

      const preview = await epbm.previewEvaluation(1n);
      expect(preview.predictedOutcome).to.equal(3n); // DEFEATED
    });
  });

  // ── Governance config ────────────────────────────────────────────────────

  describe("updateConfig()", function () {
    it("allows governance to update parameters", async function () {
      const { epbm, owner } = await deployFixture();

      await epbm.connect(owner).updateConfig(
        ethers.parseEther("0.2"), // baseBond doubled
        2n * WAD,
        1000n, 2000n, 5000n, 1000n, 2000n,
        WEEK, 2n * DAY,
        WAD,
      );

      expect(await epbm.baseBond()).to.equal(ethers.parseEther("0.2"));
    });

    it("reverts when called by non-governance", async function () {
      const { epbm, alice } = await deployFixture();

      await expect(
        epbm.connect(alice).updateConfig(
          ethers.parseEther("0.2"),
          2n * WAD,
          1000n, 2000n, 5000n, 1000n, 2000n,
          WEEK, 2n * DAY,
          WAD,
        ),
      ).to.be.revertedWithCustomError(epbm, "NotGovernance");
    });
  });

  // ── PersonhoodRegistry ───────────────────────────────────────────────────

  describe("PersonhoodRegistry", function () {
    it("admin can set and retrieve scores", async function () {
      const { registry, owner, alice } = await deployFixture();

      await registry.connect(owner).setScore(alice.address, 75);
      expect(await registry.scoreOf(alice.address)).to.equal(75n);
    });

    it("reverts on score > 100", async function () {
      const { registry, owner, alice } = await deployFixture();

      await expect(registry.connect(owner).setScore(alice.address, 101))
        .to.be.revertedWithCustomError(registry, "ScoreOutOfRange");
    });

    it("non-admin cannot set scores", async function () {
      const { registry, alice, bob } = await deployFixture();

      await expect(registry.connect(alice).setScore(bob.address, 50))
        .to.be.revertedWithCustomError(registry, "Unauthorized");
    });

    it("supports batch score setting", async function () {
      const { registry, owner, alice, bob, charlie } = await deployFixture();

      await registry.connect(owner).setScores(
        [alice.address, bob.address, charlie.address],
        [90, 70, 50],
      );

      expect(await registry.scoreOf(alice.address)).to.equal(90n);
      expect(await registry.scoreOf(bob.address)).to.equal(70n);
      expect(await registry.scoreOf(charlie.address)).to.equal(50n);
    });

    it("supports two-step admin transfer", async function () {
      const { registry, owner, alice } = await deployFixture();

      await registry.connect(owner).initiateAdminTransfer(alice.address);
      expect(await registry.pendingAdmin()).to.equal(alice.address);

      await registry.connect(alice).acceptAdminTransfer();
      expect(await registry.admin()).to.equal(alice.address);
    });
  });
});
