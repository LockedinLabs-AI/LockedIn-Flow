import assert from "node:assert/strict";
import test from "node:test";
import { linkerPrivacyFlags, privatePathFindings } from "../scripts/build-path-privacy.mjs";

const prefix = "X:\\synthetic-checkout\\";
const boundaries = [{ scope: "checkout", prefix }];

test("Windows linker records only a symbol basename", () => {
  assert.deepEqual(linkerPrivacyFlags("win32"), ["-C", "link-arg=/PDBALTPATH:%_PDB%"]);
  assert.deepEqual(linkerPrivacyFlags("linux"), []);
  assert.deepEqual(linkerPrivacyFlags("darwin"), []);
});

test("CodeView paths are classified without exposing their contents", () => {
  const record = Buffer.concat([Buffer.from("RSDS"), Buffer.alloc(20), Buffer.from(prefix + "internal-symbols.pdb\0")]);
  const findings = privatePathFindings(record, boundaries);
  assert.deepEqual(findings, [{ scope: "checkout", encoding: "utf8", kind: "debug-symbol-reference", count: 1 }]);
  assert.doesNotMatch(JSON.stringify(findings), /synthetic|internal|symbols\.pdb/);
});

test("ordinary UTF-8 and UTF-16 paths still fail the artifact boundary", () => {
  const bytes = Buffer.concat([
    Buffer.from(prefix + "synthetic.cpp\0"),
    Buffer.from(prefix.replaceAll("\\", "/") + "synthetic.rs\0", "utf16le"),
  ]);
  const findings = privatePathFindings(bytes, boundaries);
  assert.equal(findings.length, 2);
  assert.ok(findings.every(({ kind }) => kind === "source-or-data"));
  assert.deepEqual(new Set(findings.map(({ encoding }) => encoding)), new Set(["utf8", "utf16le"]));
  assert.deepEqual(privatePathFindings(Buffer.from("portable-symbols.pdb\0"), boundaries), []);
});

test("privacy diagnostics reject unrecognized labels instead of echoing them", () => {
  assert.throws(() => privatePathFindings(Buffer.alloc(0), [{ scope: "untrusted", prefix }]), /Invalid artifact/);
});
