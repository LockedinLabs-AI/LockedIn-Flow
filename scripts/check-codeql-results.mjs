import { readFileSync } from "node:fs";
import { verifyCodeQLReport } from "./lib/codeql-results.mjs";

try {
  if (process.argv.length !== 3) throw new Error("Expected one analysis report.");
  const result = verifyCodeQLReport(JSON.parse(readFileSync(process.argv[2], "utf8")));
  console.log(`CodeQL gate passed: ${result.ruleCount} rules, ${result.findingCount} findings.`);
} catch {
  // Never echo source snippets, paths, or untrusted report/error text to CI logs.
  console.error("CodeQL gate failed: analysis is missing, invalid, or contains findings.");
  process.exitCode = 1;
}
