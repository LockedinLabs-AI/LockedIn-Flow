import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
test("every application clipboard preparation is restricted to the current device", () => {
  const files = ["Sources/InsertionEngine/TextInserter.swift", ...readdirSync(path.join(root, "Sources/LockedInFlowApp"))
    .filter((name) => name.endsWith(".swift")).map((name) => `Sources/LockedInFlowApp/${name}`)];
  let protectedWrites = 0;
  for (const file of files) {
    const source = readFileSync(path.join(root, file), "utf8");
    assert.doesNotMatch(source, /\.clearContents\s*\(/, file);
    assert.doesNotMatch(source, /\.declareTypes\s*\(/, file);
    for (const match of source.matchAll(/\.prepareForNewContents\(([^\n]*)\)/g)) {
      assert.equal(match[1], "with: .currentHostOnly", file);
      protectedWrites++;
    }
  }
  assert.equal(protectedWrites, 10);
});

test("release artifact policy rejects runtime test-mode entry points", () => {
  const source = readFileSync(path.join(root, "scripts/verify-production-binary.sh"), "utf8");
  assert.match(source, /"XCTestCase"/);
  assert.match(source, /"XCTestConfigurationFilePath"/);
});
