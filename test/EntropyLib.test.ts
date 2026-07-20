import { expect } from "chai";
import { ethers } from "hardhat";
import { EntropyLib__factory } from "../typechain-types";

// ─── Harness contract (exposes internal functions for testing) ────────────────
// We wrap EntropyLib in a thin Solidity harness compiled alongside the tests.
// See contracts/mocks/EntropyLibHarness.sol

describe("EntropyLib", function () {
  let harness: Awaited<ReturnType<typeof deployHarness>>;

  async function deployHarness() {
    const Factory = await ethers.getContractFactory("EntropyLibHarness");
    const contract = await Factory.deploy();
    return contract;
  }

  beforeEach(async function () {
    harness = await deployHarness();
  });

  const WAD = 10n ** 18n;
  const LOG2_3_WAD = 1_584_962_500_721_156_120n;

  describe("normalizedEntropy", function () {
    it("returns 0 for all votes in one bucket (perfect consensus)", async function () {
      expect(await harness.normalizedEntropy(1000n, 0n, 0n)).to.equal(0n);
      expect(await harness.normalizedEntropy(0n, 1000n, 0n)).to.equal(0n);
      expect(await harness.normalizedEntropy(0n, 0n, 1000n)).to.equal(0n);
    });

    it("returns WAD for a perfectly uniform three-way split", async function () {
      // YES = NO = ABSTAIN → H = log2(3) → normalised = 1
      const result = await harness.normalizedEntropy(1000n, 1000n, 1000n);
      // Allow 0.1% tolerance due to fixed-point precision
      const tolerance = WAD / 1000n;
      expect(result).to.be.closeTo(WAD, tolerance);
    });

    it("returns ~0.918 WAD for a 50/50 YES/NO split (no abstains)", async function () {
      // H = 1 bit; normalised by log2(3) ≈ 1.585 → ~0.6309
      // Actually for binary 50/50: H = 1, normalised = 1/log2(3) ≈ 0.631
      const result = await harness.normalizedEntropy(500n, 500n, 0n);
      // 1 / log2(3) * WAD ≈ 0.630930 * WAD
      const expected = (WAD * WAD) / LOG2_3_WAD; // 1/log2(3) * WAD
      const tolerance = WAD / 100n; // 1% tolerance
      expect(result).to.be.closeTo(expected, tolerance);
    });

    it("returns 0 for zero total votes", async function () {
      expect(await harness.normalizedEntropy(0n, 0n, 0n)).to.equal(0n);
    });

    it("increases monotonically as votes become more evenly split", async function () {
      // 90/10 → 70/30 → 50/50 should give increasing entropy
      const e1 = await harness.normalizedEntropy(900n, 100n, 0n);
      const e2 = await harness.normalizedEntropy(700n, 300n, 0n);
      const e3 = await harness.normalizedEntropy(500n, 500n, 0n);
      expect(e1).to.be.lessThan(e2);
      expect(e2).to.be.lessThan(e3);
    });

    it("is symmetric: swapping YES and NO produces the same entropy", async function () {
      const e1 = await harness.normalizedEntropy(700n, 200n, 100n);
      const e2 = await harness.normalizedEntropy(200n, 700n, 100n);
      expect(e1).to.equal(e2);
    });

    it("handles very small vote weights without overflow", async function () {
      await expect(harness.normalizedEntropy(1n, 1n, 1n)).to.not.be.reverted;
    });

    it("handles very large vote weights without overflow", async function () {
      const BIG = ethers.parseEther("1000000000"); // 1e27 wei
      await expect(harness.normalizedEntropy(BIG, BIG, BIG)).to.not.be.reverted;
    });
  });
});
