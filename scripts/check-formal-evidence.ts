import { existsSync, readFileSync } from "fs";

type EvidenceEntry = {
  invariantId: string;
  title: string;
  testFiles: string[];
  proofMarkers: string[];
  artifacts: string[];
};

type EvidenceMatrix = {
  version: string;
  entries: EvidenceEntry[];
};

const invariantSpecPath = "docs/security/FORMAL_INVARIANTS_SPEC.md";
const matrixPath = "docs/security/formal-evidence-matrix.json";

function readSpecInvariantIds(path: string): string[] {
  const body = readFileSync(path, "utf8");
  const ids = [...body.matchAll(/^##\s+(INV-\d+)/gm)].map((m) => m[1]);
  return ids;
}

function main() {
  const missingFiles: string[] = [];
  for (const path of [invariantSpecPath, matrixPath]) {
    if (!existsSync(path)) missingFiles.push(path);
  }

  if (missingFiles.length > 0) {
    console.error("Formal evidence check failed: missing files");
    for (const file of missingFiles) console.error(`- ${file}`);
    process.exitCode = 1;
    return;
  }

  const matrix = JSON.parse(readFileSync(matrixPath, "utf8")) as EvidenceMatrix;
  const specIds = readSpecInvariantIds(invariantSpecPath);
  const matrixIds = matrix.entries.map((e) => e.invariantId);

  const missingFromMatrix = specIds.filter((id) => !matrixIds.includes(id));
  const missingFromSpec = matrixIds.filter((id) => !specIds.includes(id));

  const missingReferencedFiles: string[] = [];
  const missingProofMarkers: string[] = [];

  for (const entry of matrix.entries) {
    for (const path of [...entry.testFiles, ...entry.artifacts]) {
      if (!existsSync(path)) missingReferencedFiles.push(`${entry.invariantId}: ${path}`);
    }

    const testBodies = entry.testFiles
      .filter((path) => existsSync(path))
      .map((path) => readFileSync(path, "utf8"));

    for (const marker of entry.proofMarkers) {
      const found = testBodies.some((body) => body.includes(marker));
      if (!found) {
        missingProofMarkers.push(
          `${entry.invariantId}: marker not found in mapped tests: ${marker}`
        );
      }
    }
  }

  if (
    missingFromMatrix.length > 0 ||
    missingFromSpec.length > 0 ||
    missingReferencedFiles.length > 0 ||
    missingProofMarkers.length > 0
  ) {
    console.error("Formal evidence check failed.");

    if (missingFromMatrix.length > 0) {
      console.error("Invariant IDs missing from matrix:");
      for (const id of missingFromMatrix) console.error(`- ${id}`);
    }

    if (missingFromSpec.length > 0) {
      console.error("Invariant IDs present in matrix but missing in spec:");
      for (const id of missingFromSpec) console.error(`- ${id}`);
    }

    if (missingReferencedFiles.length > 0) {
      console.error("Missing referenced files:");
      for (const row of missingReferencedFiles) console.error(`- ${row}`);
    }

    if (missingProofMarkers.length > 0) {
      console.error("Missing proof markers:");
      for (const row of missingProofMarkers) console.error(`- ${row}`);
    }

    process.exitCode = 1;
    return;
  }

  console.log("Formal evidence traceability check passed.");
}

main();
