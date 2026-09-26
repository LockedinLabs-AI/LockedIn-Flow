// A successful scanner process may still report security findings. Promotion
// requires a populated analysis with no findings, not just a successful upload.
export function verifyCodeQLReport(report) {
  if (report?.version !== "2.1.0" || !Array.isArray(report.runs) || report.runs.length === 0) {
    throw new Error("CodeQL analysis is missing or invalid.");
  }
  let ruleCount = 0;
  let findingCount = 0;
  for (const run of report.runs) {
    if (run?.tool?.driver?.name !== "CodeQL" || !Array.isArray(run.results)) {
      throw new Error("CodeQL analysis has an unexpected producer or no result set.");
    }
    if (run.invocations !== undefined && (!Array.isArray(run.invocations)
        || run.invocations.some((invocation) => invocation?.executionSuccessful === false))) {
      throw new Error("CodeQL analysis did not complete successfully.");
    }
    const extensions = run.tool.extensions ?? [];
    if (!Array.isArray(extensions)) throw new Error("CodeQL rule inventory is invalid.");
    const rules = [run.tool.driver, ...extensions]
      .flatMap((component) => Array.isArray(component?.rules) ? component.rules : []);
    if (rules.length === 0 || rules.some((rule) => typeof rule?.id !== "string" || !rule.id)) {
      throw new Error("CodeQL analysis contains no usable rule inventory.");
    }
    ruleCount += rules.length;
    // Do not exempt old findings, low-severity results, or SARIF suppressions.
    findingCount += run.results.length;
  }
  if (findingCount !== 0) throw new Error(`CodeQL reported ${findingCount} finding(s).`);
  return { runCount: report.runs.length, ruleCount, findingCount };
}
