import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

test("dictation delivery diagnostics contain only a fixed completion event", () => {
  const source = readFileSync(new URL("../../Sources/LockedInFlowApp/DictationController.swift", import.meta.url), "utf8");
  const calls = [...source.matchAll(/FlowLog\.pipeline\(\s*([^;]*?)\s*\)/g)];
  assert.deepEqual(calls.map((match) => match[1]), ['"dictation inserted"']);
});
