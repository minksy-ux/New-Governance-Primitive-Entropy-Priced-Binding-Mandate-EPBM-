import { existsSync, statSync, readFileSync, readdirSync } from "fs";

const requiredFiles = [
  "docs/security/AUDIT_READY_STAGE.md",
  "docs/security/SECURITY_REPORT_TEMPLATE.md",
  "docs/security/FORMAL_INVARIANTS_SPEC.md",
  "docs/security/remediation-log.csv",
  "docs/production/PRODUCTION_NETWORK_STAGE.md",
  "docs/governance/verifier-admission-removal-constitution.md",
  "docs/governance/dispute-process.md",
  "docs/governance/incident-postmortem-template.md",
  "docs/governance/parameter-policy.md",
  "docs/operations/drills/capture-event-drill.md",
  "docs/operations/drills/disputed-fork-drill.md",
  "docs/operations/drills/verifier-compromise-drill.md",
];

const runDir = "docs/operations/drills/runs";
const requiredRunPrefixes = [
  "capture-event-drill-run-",
  "disputed-fork-drill-run-",
  "verifier-compromise-drill-run-",
];

function isNonEmpty(path: string): boolean {
  if (!existsSync(path)) return false;
  const stats = statSync(path);
  return stats.isFile() && stats.size > 0;
}

function hasRequiredSection(path: string, marker: string): boolean {
  const body = readFileSync(path, "utf8");
  return body.includes(marker);
}

function main() {
  const missingOrEmpty = requiredFiles.filter((path) => !isNonEmpty(path));

  const runDirExists = existsSync(runDir) && statSync(runDir).isDirectory();
  const runFileNames = runDirExists
    ? readdirSync(runDir).filter((name) => name.endsWith(".md"))
    : [];

  const missingRunKinds = requiredRunPrefixes.filter(
    (prefix) =>
      !runFileNames.some((name) => {
        const withoutDate = name.replace(/^\d{4}-\d{2}-\d{2}-/, "");
        return withoutDate.startsWith(prefix);
      }),
  );

  const runFiles = runFileNames.map((name) => `${runDir}/${name}`);
  const runFilesMissingEvidence = runFiles.filter((path) => !hasRequiredSection(path, "## Evidence"));

  if (missingOrEmpty.length > 0 || !runDirExists || missingRunKinds.length > 0 || runFilesMissingEvidence.length > 0) {
    console.error("Maturity artifact gate failed.");

    if (missingOrEmpty.length > 0) {
      console.error("Missing or empty files:");
      for (const path of missingOrEmpty) {
        console.error(`- ${path}`);
      }
    }

    if (runFilesMissingEvidence.length > 0) {
      console.error("Run files missing evidence sections:");
      for (const path of runFilesMissingEvidence) {
        console.error(`- ${path}`);
      }
    }

    if (!runDirExists) {
      console.error(`Run evidence directory missing: ${runDir}`);
    }

    if (missingRunKinds.length > 0) {
      console.error("Missing required drill run types (expected at least one .md each):");
      for (const prefix of missingRunKinds) {
        console.error(`- ${prefix}`);
      }
    }

    process.exitCode = 1;
    return;
  }

  console.log("Maturity artifact gate passed.");
}

main();
