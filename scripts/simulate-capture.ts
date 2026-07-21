import { randomInt } from "crypto";

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

function parseIntArg(name: string, fallback: number): number {
  const key = `--${name}`;
  const idx = process.argv.indexOf(key);
  if (idx === -1 || idx + 1 >= process.argv.length) return fallback;
  const value = Number(process.argv[idx + 1]);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`Invalid value for ${key}: ${process.argv[idx + 1]}`);
  }
  return Math.floor(value);
}

function parseIntEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`Invalid value for env ${name}: ${raw}`);
  }
  return Math.floor(value);
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

function main() {
  const cfg: SimulationConfig = {
    rounds: parseIntArg("rounds", parseIntEnv("ROUNDS", 5000)),
    baseQuorumBps: parseIntArg("baseQuorumBps", parseIntEnv("BASE_QUORUM_BPS", 1000)),
    quorumEntropyFactorBps: parseIntArg(
      "quorumEntropyFactorBps",
      parseIntEnv("QUORUM_ENTROPY_FACTOR_BPS", 2000),
    ),
    passageThresholdBps: parseIntArg("passageThresholdBps", parseIntEnv("PASSAGE_THRESHOLD_BPS", 5000)),
    passageEntropyFactorBps: parseIntArg(
      "passageEntropyFactorBps",
      parseIntEnv("PASSAGE_ENTROPY_FACTOR_BPS", 1000),
    ),
    vetoThresholdBps: parseIntArg("vetoThresholdBps", parseIntEnv("VETO_THRESHOLD_BPS", 2000)),
  };

  const result = runSimulation(cfg);

  console.log("EPBM cartel/capture simulation");
  console.log("-----------------------------");
  console.log(`rounds:          ${cfg.rounds}`);
  console.log(`passed:          ${result.passed}`);
  console.log(`defeated:        ${result.defeated}`);
  console.log(`vetoed:          ${result.vetoed}`);
  console.log(`cartelWon:       ${result.cartelWon}`);
  console.log(`minorityVetoed:  ${result.minorityVetoed}`);

  const cartelWinRate = (result.cartelWon / cfg.rounds) * 100;
  console.log(`cartelWinRate:   ${cartelWinRate.toFixed(2)}%`);
}

main();
