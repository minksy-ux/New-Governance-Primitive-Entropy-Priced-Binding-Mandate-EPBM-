import { randomInt } from "crypto";
import { writeFileSync } from "fs";

const BPS_DENOM = 10_000;

type SimulationConfig = {
  rounds: number;
  baseQuorumBps: number;
  quorumEntropyFactorBps: number;
  passageThresholdBps: number;
  passageEntropyFactorBps: number;
  vetoThresholdBps: number;
};

type SimulationResult = {
  passed: number;
  defeated: number;
  vetoed: number;
  cartelWon: number;
  minorityVetoed: number;
};

function parseIntEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`Invalid value for env ${name}: ${raw}`);
  }
  return Math.floor(value);
}

function parseIntListEnv(name: string, fallback: number[]): number[] {
  const raw = process.env[name];
  if (!raw) return fallback;
  const values = raw
    .split(",")
    .map((v) => v.trim())
    .filter((v) => v.length > 0)
    .map((v) => Number(v));

  if (values.length === 0) {
    throw new Error(`No values provided for env ${name}`);
  }

  for (const value of values) {
    if (!Number.isFinite(value) || value < 0) {
      throw new Error(`Invalid numeric value in env ${name}: ${value}`);
    }
  }

  return values.map((v) => Math.floor(v));
}

function normalizedEntropyWad(yes: number, no: number, abstain: number): bigint {
  const total = yes + no + abstain;
  if (total === 0) return 0n;

  const parts = [yes, no, abstain].filter((x) => x > 0);
  if (parts.length <= 1) return 0n;

  const probs = parts.map((x) => x / total);
  const h = -probs.reduce((acc, p) => acc + p * Math.log(p), 0);
  const hMax = Math.log(3);
  const normalized = h / hMax;
  return BigInt(Math.floor(normalized * 1e18));
}

function runSimulation(cfg: SimulationConfig): SimulationResult {
  const result: SimulationResult = {
    passed: 0,
    defeated: 0,
    vetoed: 0,
    cartelWon: 0,
    minorityVetoed: 0,
  };

  for (let i = 0; i < cfg.rounds; i++) {
    const cartelShareBps = randomInt(1000, 9001);
    const turnoutBps = randomInt(2000, 10001);
    const noBiasBps = randomInt(0, 10001);

    const eligible = 1_000_000;
    const voted = Math.floor((eligible * turnoutBps) / BPS_DENOM);

    const cartelVotes = Math.floor((voted * cartelShareBps) / BPS_DENOM);
    const othersVotes = voted - cartelVotes;

    const cartelNo = Math.floor((cartelVotes * noBiasBps) / BPS_DENOM);
    const cartelYes = cartelVotes - cartelNo;

    const othersNo = Math.floor((othersVotes * randomInt(0, 3001)) / BPS_DENOM);
    const othersYes = othersVotes - othersNo;

    const abstain = randomInt(0, Math.floor(voted * 0.2) + 1);
    const yes = Math.max(0, cartelYes + othersYes - Math.floor(abstain / 2));
    const no = Math.max(0, cartelNo + othersNo - Math.ceil(abstain / 2));

    const entropy = normalizedEntropyWad(yes, no, abstain);
    const adjustedQuorumBps = Math.min(
      BPS_DENOM,
      cfg.baseQuorumBps + Math.floor((cfg.quorumEntropyFactorBps * Number(entropy)) / 1e18),
    );
    const adjustedPassageBps = Math.min(
      BPS_DENOM,
      cfg.passageThresholdBps + Math.floor((cfg.passageEntropyFactorBps * Number(entropy)) / 1e18),
    );

    const quorumWeight = Math.floor((eligible * adjustedQuorumBps) / BPS_DENOM);
    const quorumMet = yes + no + abstain >= quorumWeight;

    const vetoed = Math.floor((no * BPS_DENOM) / eligible) > cfg.vetoThresholdBps;
    const contested = yes + no;
    const passed =
      !vetoed &&
      quorumMet &&
      contested > 0 &&
      Math.floor((yes * BPS_DENOM) / contested) > adjustedPassageBps;

    if (vetoed) result.vetoed += 1;
    else if (passed) result.passed += 1;
    else result.defeated += 1;

    const cartelWon = cartelYes > cartelNo && passed;
    if (cartelWon) result.cartelWon += 1;

    const minorityVetoed = cartelShareBps < 5_000 && vetoed;
    if (minorityVetoed) result.minorityVetoed += 1;
  }

  return result;
}

function toRate(n: number, d: number): string {
  if (d === 0) return "0.0000";
  return (n / d).toFixed(4);
}

function main() {
  const rounds = parseIntEnv("ROUNDS", 3000);

  const baseQuorumBpsList = parseIntListEnv("BASE_QUORUM_BPS_LIST", [800, 1000, 1200]);
  const quorumEntropyFactorBpsList = parseIntListEnv("QUORUM_ENTROPY_FACTOR_BPS_LIST", [1500, 2000, 2500]);
  const passageThresholdBpsList = parseIntListEnv("PASSAGE_THRESHOLD_BPS_LIST", [5000, 5500]);
  const passageEntropyFactorBpsList = parseIntListEnv("PASSAGE_ENTROPY_FACTOR_BPS_LIST", [1000, 1500]);
  const vetoThresholdBpsList = parseIntListEnv("VETO_THRESHOLD_BPS_LIST", [1500, 2000, 2500]);

  const lines: string[] = [];
  lines.push(
    [
      "baseQuorumBps",
      "quorumEntropyFactorBps",
      "passageThresholdBps",
      "passageEntropyFactorBps",
      "vetoThresholdBps",
      "rounds",
      "passed",
      "defeated",
      "vetoed",
      "cartelWon",
      "minorityVetoed",
      "passRate",
      "vetoRate",
      "cartelWinRate",
      "minorityVetoRate",
    ].join(","),
  );

  for (const baseQuorumBps of baseQuorumBpsList) {
    for (const quorumEntropyFactorBps of quorumEntropyFactorBpsList) {
      for (const passageThresholdBps of passageThresholdBpsList) {
        for (const passageEntropyFactorBps of passageEntropyFactorBpsList) {
          for (const vetoThresholdBps of vetoThresholdBpsList) {
            const cfg: SimulationConfig = {
              rounds,
              baseQuorumBps,
              quorumEntropyFactorBps,
              passageThresholdBps,
              passageEntropyFactorBps,
              vetoThresholdBps,
            };

            const result = runSimulation(cfg);
            lines.push(
              [
                cfg.baseQuorumBps,
                cfg.quorumEntropyFactorBps,
                cfg.passageThresholdBps,
                cfg.passageEntropyFactorBps,
                cfg.vetoThresholdBps,
                cfg.rounds,
                result.passed,
                result.defeated,
                result.vetoed,
                result.cartelWon,
                result.minorityVetoed,
                toRate(result.passed, cfg.rounds),
                toRate(result.vetoed, cfg.rounds),
                toRate(result.cartelWon, cfg.rounds),
                toRate(result.minorityVetoed, cfg.rounds),
              ].join(","),
            );
          }
        }
      }
    }
  }

  const csv = lines.join("\n");
  const outFile = process.env.OUT_FILE;

  if (outFile) {
    writeFileSync(outFile, `${csv}\n`, "utf8");
    console.log(`Wrote sweep CSV to ${outFile}`);
  } else {
    console.log(csv);
  }
}

main();
