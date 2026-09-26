import assert from "node:assert/strict";
import test from "node:test";
import { verifyCodeQLReport } from "../../scripts/lib/codeql-results.mjs";

// Synthetic SARIF matching CodeQL's separate language-query-pack structure.
const cleanReport = () => ({
  version: "2.1.0",
  runs: [{
    tool: { driver: { name: "CodeQL" }, extensions: [
      { name: "codeql/swift-queries", rules: [{ id: "swift/synthetic-security-rule" }] },
    ] },
    results: [],
  }],
});

test("CodeQL gate accepts a populated analysis with no findings", () => {
  assert.deepEqual(verifyCodeQLReport(cleanReport()), { runCount: 1, ruleCount: 1, findingCount: 0 });
});

test("CodeQL gate blocks findings regardless of severity, baseline, or suppression", () => {
  for (const extra of [{}, { level: "note" }, { baselineState: "unchanged" }, { suppressions: [{ kind: "external" }] }]) {
    const report = cleanReport();
    report.runs[0].results.push({ ruleId: "swift/synthetic-security-rule", ...extra });
    assert.throws(() => verifyCodeQLReport(report), /reported 1 finding/);
  }
});

test("CodeQL gate rejects absent, empty, or unknown analysis reports", () => {
  for (const report of [undefined, {}, { version: "2.1.0", runs: [] }, { ...cleanReport(), version: "unknown" }]) {
    assert.throws(() => verifyCodeQLReport(report));
  }
  const report = cleanReport();
  report.runs[0].tool.driver.name = "Unexpected scanner";
  assert.throws(() => verifyCodeQLReport(report));
});

test("CodeQL gate rejects missing results or missing rule coverage", () => {
  const noResults = cleanReport();
  delete noResults.runs[0].results;
  assert.throws(() => verifyCodeQLReport(noResults));
  const noRules = cleanReport();
  noRules.runs[0].tool.extensions = [];
  assert.throws(() => verifyCodeQLReport(noRules));
});

test("CodeQL gate rejects failed invocations and checks every analysis run", () => {
  const failed = cleanReport();
  failed.runs[0].invocations = [{ executionSuccessful: false }];
  assert.throws(() => verifyCodeQLReport(failed));
  const multiple = cleanReport();
  multiple.runs.push({ ...cleanReport().runs[0], results: [{ ruleId: "swift/synthetic-security-rule" }] });
  assert.throws(() => verifyCodeQLReport(multiple), /reported 1 finding/);
});
