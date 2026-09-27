import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdtemp, writeFile, symlink, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { digest, inspectTar, inspectPackage, packageMetadata, standardTool, limits, verifyBuildIdentity, boundedFile } from "../scripts/linux-package-evidence.mjs";

// Only synthetic, in-memory USTAR fixtures. No application or model is run.
const resourceRoot = "usr/lib/lockedin-flow-desktop";
const payload = [
  ["usr/bin/lockedin-flow-desktop", Buffer.from([127, 69, 76, 70, 1, 2, 3])],
  [resourceRoot + "/models/ggml-base.en.bin", Buffer.from("synthetic-model")],
  ...["SBOM.cdx.json", "THIRD-PARTY-NOTICES.txt", "LICENSE.txt", "MODEL.json"].map((label) => [resourceRoot + "/compliance/" + label, Buffer.from("synthetic-" + label)]),
  ["usr/lib/synthetic-native.so", Buffer.from([127, 69, 76, 70, 9])],
];
const expected = {
  application: digest(payload[0][1]), model: digest(payload[1][1]),
  ...Object.fromEntries(payload.slice(2, 6).map(([name, bytes]) => [name.split("/").at(-1), digest(bytes)])),
};
function header(name, size, { type = "0", mode = 0o644, link = "", prefix = "", gnu = false } = {}) {
  const out = Buffer.alloc(512);
  const octal = (value, at, length) => out.write(value.toString(8).padStart(length - 1, "0") + "\0", at, length);
  out.write(name, 0, 100);
  octal(mode, 100, 8);
  octal(0, 108, 8);
  octal(0, 116, 8);
  octal(size, 124, 12);
  octal(0, 136, 12);
  out.fill(32, 148, 156);
  out.write(type, 156);
  out.write(link, 157, 100);
  out.write(gnu ? "ustar  \0" : "ustar\0" + "00", 257);
  if (gnu) { octal(0, 329, 8); octal(0, 337, 8); }
  out.write(prefix, 345, 155);
  out.write(out.reduce((sum, byte) => sum + byte, 0).toString(8).padStart(6, "0") + "\0 ", 148);
  return out;
}
function tar(files = payload) {
  return Buffer.concat([
    ...files.flatMap(([name, value, options]) => {
      const bytes = Buffer.from(value);
      return [header(name, bytes.length, options), bytes, Buffer.alloc((512 - bytes.length % 512) % 512)];
    }), Buffer.alloc(1024),
  ]);
}
function packageBytes(format) {
  const bytes = Buffer.alloc(128);
  if (format === "deb") bytes.write("!<arch>\n");
  if (format === "rpm") bytes.set([237, 171, 238, 219]);
  if (format === "appimage") { bytes.set([127, 69, 76, 70]); bytes.set([65, 73, 2], 8); }
  return bytes;
}

test("payload hashes bind the exact binary, model and four compliance resources", () => {
  const files = inspectTar(tar(), expected);
  assert.equal(files.length, payload.length);
  assert.equal(files.filter((file) => file.verifiedResource).length, 6);
  assert.equal(files.filter((file) => file.elf).length, 2);
  assert.ok(files.every((file) => file.componentMapping === "unresolved"));
  assert.ok(files.every((file) => /^[a-f0-9]{64}$/.test(file.pathSha256)));
  assert.doesNotMatch(JSON.stringify(files), /synthetic-native|synthetic-model|usr\//);
});

test("bounded input reader rejects oversized files, empty files, directories, FIFOs and symlinks", { skip: process.platform === "win32" }, async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "flow-inventory-fixture-"));
  try {
    const file = path.join(directory, "synthetic");
    await writeFile(file, "synthetic", { flag: "wx" });
    assert.equal((await boundedFile(file, 9)).toString(), "synthetic");
    await assert.rejects(boundedFile(file, 3));
    await assert.rejects(boundedFile(directory, 1024));
    await writeFile(path.join(directory, "empty"), "", { flag: "wx" });
    await assert.rejects(boundedFile(path.join(directory, "empty"), 1024));
    await symlink(file, path.join(directory, "link"));
    await assert.rejects(boundedFile(path.join(directory, "link"), 1024));
    standardTool("/usr/bin/mkfifo", [path.join(directory, "fifo")]);
    await assert.rejects(boundedFile(path.join(directory, "fifo"), 1024));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("build identity rejects mismatched checkout, target, locks, dirty state and duplicate properties", () => {
  const revision = "a".repeat(40), cargo = "b".repeat(64), npm = "c".repeat(64);
  const properties = Object.entries({
    "lockedin:source-revision": revision, "lockedin:source-state": "clean",
    "lockedin:target": "x86_64-unknown-linux-gnu", "lockedin:cargo-lock-sha256": cargo, "lockedin:npm-lock-sha256": npm,
  }).map(([name, value]) => ({ name, value }));
  const sbom = { bomFormat: "CycloneDX", specVersion: "1.6", metadata: { properties } };
  verifyBuildIdentity(sbom, revision, cargo, npm);
  for (let index = 0; index < properties.length; index++) {
    const changed = structuredClone(sbom);
    changed.metadata.properties[index].value = "different";
    assert.throws(() => verifyBuildIdentity(changed, revision, cargo, npm));
  }
  sbom.metadata.properties.push(properties[0]);
  assert.throws(() => verifyBuildIdentity(sbom, revision, cargo, npm));
});

test("rejects traversal, absolute paths, unsafe characters, aliases and non-directory ancestors", () => {
  for (const name of ["../escape", "/absolute", "usr/../escape", "usr//file", "usr/./file", "C:\\escape", "usr/hidden\nvalue"])
    assert.throws(() => inspectTar(tar([...payload, [name, "x"]]), expected), /details withheld/);
  assert.throws(() => inspectTar(tar([...payload, ["./" + payload[0][0], payload[0][1]]]), expected));
  assert.throws(() => inspectTar(tar([...payload, ["usr", "not-a-directory"]]), expected));
});

test("rejects links (including otherwise safe ones), devices, FIFOs, extensions and privilege bits", () => {
  for (const type of ["1", "2", "3", "4", "6", "x", "g", "S"])
    assert.throws(() => inspectTar(tar([...payload, ["usr/link", "", { type, link: "../private-target" }]]), expected));
  assert.throws(() => inspectTar(tar([...payload, ["usr/link", "", { type: "2", link: "bin/lockedin-flow-desktop" }]]), expected));
  for (const mode of [0o4755, 0o2755, 0o1777])
    assert.throws(() => inspectTar(tar([...payload, ["usr/privileged", "x", { mode }]]), expected));
});

test("rejects bad checksums, missing terminators, hidden tails, truncated and oversized members", () => {
  const corrupt = tar(); corrupt[20] ^= 1;
  assert.throws(() => inspectTar(corrupt, expected));
  assert.throws(() => inspectTar(tar().subarray(0, -1024), expected));
  assert.throws(() => inspectTar(tar().subarray(0, -1), expected));
  assert.throws(() => inspectTar(Buffer.concat([tar(), tar()]), expected));
  assert.throws(() => inspectTar(Buffer.concat([header("usr/huge", limits.file + 1), Buffer.alloc(1024)]), expected));
  assert.throws(() => inspectTar(Buffer.concat([header("usr/missing", 4096), Buffer.alloc(1024)]), expected));
});

test("entry count is bounded even when members contain no data", () => {
  const files = Array.from({ length: limits.entries + 1 }, (_, index) => ["usr/entry-" + index, ""]);
  assert.throws(() => inspectTar(tar(files), expected));
});

test("rejects missing, changed, duplicated or relocated staged resources", () => {
  assert.throws(() => inspectTar(tar(payload.slice(1)), expected));
  assert.throws(() => inspectTar(tar(), { ...expected, model: "0".repeat(64) }));
  assert.throws(() => inspectTar(tar(), { ...expected, application: "0".repeat(64) }));
  assert.throws(() => inspectTar(tar([...payload, ["usr/extra/compliance/MODEL.json", payload[5][1]]]), expected));
  const moved = payload.map(([name, bytes]) => [name.replace("/compliance/", "/elsewhere/compliance/"), bytes]);
  assert.throws(() => inspectTar(tar(moved), expected));
});

test("metadata uses actual query fields and hashes unreviewed dependency declarations", () => {
  const data = packageMetadata("rpm", "lockedin-flow\n0.5.0-1\nx86_64\n", "libexample.so.1()(64bit)\n/private-synthetic/requirement\n");
  assert.equal(data.declaredVersion, "0.5.0-1");
  assert.equal(data.declaredOsDependencies.scope, "requirements-not-bundled-components");
  assert.equal(data.declaredOsDependencies.recordSha256.length, 2);
  assert.doesNotMatch(JSON.stringify(data), /libexample|private-synthetic/);
  for (const identity of ["foreign\n0.5.0\namd64", "lockedin-flow\nprivate/value\namd64", "lockedin-flow\n0.5.0-client-private\namd64", "lockedin-flow\n0.5.0\narm64", "lockedin-flow\n0.5.0\namd64\nextra"])
    assert.throws(() => packageMetadata("deb", identity, ""));
  assert.throws(() => packageMetadata("deb", "lockedin-flow\n0.5.0\namd64", "injected\u001b[31m"));
  assert.throws(() => packageMetadata("deb", "x".repeat(limits.metadata + 1), ""));
});

test("DEB adapter queries metadata and checks the bounded original stream without normalization", () => {
  const calls = [];
  const run = (command, args, input, cap) => {
    calls.push({ command, args, input, cap });
    if (args[0] === "--field") return Buffer.from(({ Package: "lockedin-flow", Version: "0.5.0-alpha.1", Architecture: "amd64", Depends: "libc6", "Pre-Depends": "" })[args[2]] + "\n");
    assert.equal(command, "/usr/bin/dpkg-deb");
    assert.deepEqual(args, ["--fsys-tarfile", "/synthetic/input.deb"]);
    assert.equal(cap, limits.payload);
    return tar();
  };
  const bytes = packageBytes("deb");
  const report = inspectPackage("deb", "/synthetic/input.deb", bytes, expected, run);
  assert.equal(report.status, "payload-inspected");
  assert.equal(report.sha256, digest(bytes));
  assert.equal(report.licenseReview, "unresolved");
  assert.ok(calls.every(({ args }) => !args.includes("--install") && !args.includes("-x")));
  assert.doesNotMatch(JSON.stringify(report), /synthetic\/input|libc6/);
});

test("DEB adapter validates original framing before any normalizer can hide trailing data", () => {
  const clean = tar(payload.slice(0, 6));
  const concatenated = Buffer.concat([clean, tar([["usr/trailing-synthetic-link", "", { type: "2", link: "../../outside-synthetic" }]])]);
  const tail = Buffer.concat([clean, Buffer.alloc(512, 0x58)]);
  const calls = [];
  for (const [stream, size, status] of [[clean, 7168, "payload-inspected"], [concatenated, 8704, "unverified"], [tail, 7680, "unverified"]]) {
    assert.equal(stream.length, size);
    const run = (command, args) => {
      calls.push(command);
      if (command === "/usr/bin/bsdtar") return clean; // Model the normalizer discarding trailing data.
      assert.equal(command, "/usr/bin/dpkg-deb");
      if (args[0] === "--fsys-tarfile") return stream;
      return Buffer.from(({ Package: "lockedin-flow", Version: "0.5.0", Architecture: "amd64", Depends: "", "Pre-Depends": "" })[args[2]] + "\n");
    };
    const report = inspectPackage("deb", "/synthetic/owned.deb", packageBytes("deb"), expected, run);
    assert.equal(report.status, status, `Original ${size}-byte stream must determine inspection status`);
    if (status === "unverified") {
      assert.equal(report.files, null);
      assert.equal(report.reason, "tool-or-payload-validation-failed");
    }
  }
  assert.ok(calls.every((command) => command === "/usr/bin/dpkg-deb"), "Original bytes must not be normalized");
});

test("GNU without producer metadata and PAX stay unverified instead of being normalized", () => {
  const gnu = tar();
  gnu.write("ustar  \0", 257);
  gnu.fill(32, 148, 156);
  gnu.write(gnu.subarray(0, 512).reduce((sum, byte) => sum + byte, 0).toString(8).padStart(6, "0") + "\0 ", 148);
  const pax = tar([["PaxHeader", "", { type: "x" }], ...payload]);
  for (const stream of [gnu, pax]) {
    const calls = [];
    const run = (command, args) => {
      calls.push(command);
      if (command === "/usr/bin/bsdtar") return tar();
      assert.equal(command, "/usr/bin/dpkg-deb");
      if (args[0] === "--fsys-tarfile") return stream;
      return Buffer.from(({ Package: "lockedin-flow", Version: "0.5.0", Architecture: "amd64", Depends: "", "Pre-Depends": "" })[args[2]] + "\n");
    };
    const report = inspectPackage("deb", "/synthetic/unsupported.deb", packageBytes("deb"), expected, run);
    assert.equal(report.status, "unverified");
    assert.equal(report.files, null);
    assert.ok(calls.every((command) => command === "/usr/bin/dpkg-deb"));
  }
});

// tar 0.4.46 new_gnu + deterministic Unix metadata, with no extension records.
const ordinaryGnu = () => tar(payload.slice(0, 6).map(([name, bytes], index) => [name, bytes, { gnu: true, mode: index === 0 ? 0o755 : 0o644 }]));
function checksumFirstHeader(stream) {
  stream.fill(32, 148, 156);
  stream.write(stream.subarray(0, 512).reduce((sum, byte) => sum + byte, 0).toString(8).padStart(6, "0") + "\0 ", 148);
  return stream;
}
function inspectOriginalDeb(stream) {
  const calls = [];
  const run = (command, args) => {
    calls.push(command);
    assert.equal(command, "/usr/bin/dpkg-deb");
    if (args[0] === "--fsys-tarfile") return stream;
    return Buffer.from(({ Package: "lockedin-flow", Version: "0.5.0", Architecture: "amd64", Depends: "", "Pre-Depends": "" })[args[2]] + "\n");
  };
  const report = inspectPackage("deb", "/synthetic/ordinary-gnu.deb", packageBytes("deb"), expected, run);
  assert.ok(calls.every((command) => command === "/usr/bin/dpkg-deb"));
  return report;
}

test("ordinary producer GNU files and directories are inspected directly with permission-only modes", () => {
  const stream = ordinaryGnu();
  assert.equal(stream.length, 7168);
  assert.equal(inspectTar(stream, expected).length, 6);
  const report = inspectOriginalDeb(stream);
  assert.equal(report.status, "payload-inspected");
  assert.equal(report.files.find((file) => file.verifiedResource === "application").mode, 0o755);
  assert.ok(report.files.filter((file) => file.verifiedResource !== "application").every((file) => file.mode === 0o644));
  const withDirectory = tar([["usr", "", { gnu: true, type: "5", mode: 0o755 }], ...payload.map(([name, bytes]) => [name, bytes, { gnu: true }])]);
  assert.equal(inspectOriginalDeb(withDirectory).status, "payload-inspected");
  assert.equal(inspectTar(withDirectory, expected).find((file) => file.type === "directory").mode, 0o755);
});

test("GNU fields cannot become a USTAR prefix or activate time/offset/sparse extensions", () => {
  for (const offset of [345, 357, 369, 381, 385, 386, 410, 434, 458, 482, 483, 495, 511]) {
    const stream = ordinaryGnu(); stream[offset] = 49; checksumFirstHeader(stream);
    assert.throws(() => inspectTar(stream, expected));
    assert.equal(inspectOriginalDeb(stream).status, "unverified");
  }
  for (const type of ["L", "K", "S", "x", "g", "1", "2", "3", "4", "6"]) {
    const stream = ordinaryGnu(); stream.write(type, 156); checksumFirstHeader(stream);
    assert.throws(() => inspectTar(stream, expected));
    assert.equal(inspectOriginalDeb(stream).files, null);
  }
});

test("GNU mode validation does not mask file-type or privilege bits", () => {
  for (const mode of [0o100644, 0o100755, 0o4755, 0o2755, 0o1777, 0o666]) {
    const stream = ordinaryGnu(); stream.write(mode.toString(8).padStart(7, "0") + "\0", 100); checksumFirstHeader(stream);
    assert.throws(() => inspectTar(stream, expected));
    assert.equal(inspectOriginalDeb(stream).status, "unverified");
  }
  for (const mode of [0o644, 0o40755]) {
    const stream = tar([["usr", "", { gnu: true, type: "5", mode }], ...payload.map(([name, bytes]) => [name, bytes, { gnu: true }])]);
    assert.equal(inspectOriginalDeb(stream).status, "unverified");
  }
});

test("GNU producer metadata and magic are byte-checked, not silently reinterpreted", () => {
  for (const offset of [108, 116, 265, 297, 329, 337, 136]) {
    const stream = ordinaryGnu(); stream[offset] = offset === 136 ? 90 : 49; checksumFirstHeader(stream);
    assert.equal(inspectOriginalDeb(stream).status, "unverified");
  }
  for (const offset of [257, 263]) {
    const stream = ordinaryGnu(); stream[offset] |= 128; checksumFirstHeader(stream);
    assert.equal(inspectOriginalDeb(stream).status, "unverified");
  }
});

test("GNU acceptance preserves full-stream framing, no-links and path guards", () => {
  const clean = ordinaryGnu();
  const hidden = Buffer.concat([clean, tar([["usr/trailing-link", "", { gnu: true, type: "2", link: "../../outside" }]])]);
  const tail = Buffer.concat([clean, Buffer.alloc(512, 0x58)]);
  assert.equal(hidden.length, 8704);
  assert.equal(tail.length, 7680);
  for (const stream of [hidden, tail, clean.subarray(0, -512)]) {
    assert.throws(() => inspectTar(stream, expected));
    const report = inspectOriginalDeb(stream);
    assert.equal(report.status, "unverified");
    assert.equal(report.files, null);
  }
  for (const name of ["../outside", "/absolute", "usr/../escape", "usr/bin/lockedin-flow-desktop"]) {
    const stream = tar([...payload.map(([entry, bytes]) => [entry, bytes, { gnu: true }]), [name, "x", { gnu: true }]]);
    assert.equal(inspectOriginalDeb(stream).status, "unverified");
  }
});

test("RPM metadata is retained without claiming original payload inspection or invoking a normalizer", () => {
  const calls = [];
  const run = (command, args) => {
    calls.push(command);
    assert.equal(command, "/usr/bin/rpm");
    if (args.includes("--queryformat")) return Buffer.from("lockedin-flow\n0.5.0-1\nx86_64\n");
    if (args.includes("--requires")) return Buffer.from("libc.so.6\n");
    assert.fail("Only RPM metadata queries are permitted");
  };
  const report = inspectPackage("rpm", "/synthetic/misleading-9.9.rpm", packageBytes("rpm"), expected, run);
  assert.equal(report.status, "unverified");
  assert.equal(report.reason, "rpm-original-payload-validation-unavailable");
  assert.equal(report.files, null);
  assert.equal(report.sha256, digest(packageBytes("rpm")));
  assert.equal(calls.length, 2);
  assert.ok(calls.every((command) => command === "/usr/bin/rpm"));
  assert.equal(report.metadata.declaredVersion, "0.5.0-1");
});

test("tool errors and malformed payloads stay unverified with no raw diagnostics", () => {
  const report = inspectPackage("rpm", "/synthetic/private.rpm", packageBytes("rpm"), expected, () => { throw new Error("private-diagnostic-secret"); });
  assert.equal(report.status, "unverified");
  assert.equal(report.files, null);
  assert.doesNotMatch(JSON.stringify(report), /private|secret/);
  assert.throws(() => standardTool(process.execPath, ["-e", "process.stderr.write('private-diagnostic-secret'); process.exit(1)"]), /^Error: Package evidence rejected; input details withheld\.$/);
  assert.throws(() => standardTool(process.execPath, ["-e", "process.stdout.write('x'.repeat(4096))"], undefined, 128), /details withheld/);
});

test("AppImage is hashed but explicitly unverified; its runtime is never invoked", () => {
  const bytes = packageBytes("appimage");
  const report = inspectPackage("appimage", "/synthetic/app.AppImage", bytes, expected, () => assert.fail("Must not run any AppImage helper"));
  assert.equal(report.sha256, digest(bytes));
  assert.equal(report.status, "unverified");
  assert.equal(report.reason, "appimage-payload-reader-not-implemented");
  assert.equal(report.files, null);
  assert.throws(() => inspectPackage("appimage", "unused", packageBytes("deb"), expected));
});

test("installed bsdtar converts a synthetic stream without hiding unsafe names", { skip: !existsSync("/usr/bin/bsdtar") }, () => {
  const converted = standardTool("/usr/bin/bsdtar", ["-cPf", "-", "--format=ustar", "@-"], tar(), limits.payload);
  assert.deepEqual(inspectTar(converted, expected), inspectTar(tar(), expected));
  const unsafe = standardTool("/usr/bin/bsdtar", ["-cPf", "-", "--format=ustar", "@-"], tar([...payload, ["/absolute-synthetic", "x"]]), limits.payload);
  assert.throws(() => inspectTar(unsafe, expected));
  const cpio = standardTool("/usr/bin/bsdtar", ["-cPf", "-", "--format=newc", "@-"], tar(), limits.payload);
  const normalized = standardTool("/usr/bin/bsdtar", ["-cPf", "-", "--format=ustar", "@-"], cpio, limits.payload);
  assert.deepEqual(inspectTar(normalized, expected), inspectTar(tar(), expected));
});

test("DEB failure stages distinguish tools and validation without exposing exception content", () => {
  const inspect = ({ failure = -1, version = "0.5.0-alpha.1", stream = tar(), resources = expected } = {}) => {
    let call = 0;
    const values = ["locked-in-flow", version, "amd64", "libc6", ""];
    return inspectPackage("deb", "/synthetic/input.deb", packageBytes("deb"), resources, () => {
      const index = call++;
      if (index === failure) throw Object.assign(new Error("synthetic-private-diagnostics"), { category: "synthetic-private-category" });
      return index < 5 ? Buffer.from(values[index] + "\n") : stream;
    });
  };
  for (const [failure, stage] of [[0, "identity-query"], [1, "identity-query"], [2, "identity-query"], [3, "dependency-query"], [4, "dependency-query"], [5, "payload-read"]]) {
    const result = inspect({ failure });
    assert.equal(result.failureStage, stage);
    assert.equal(result.status, "unverified");
    assert.equal(result.metadata, null);
    assert.equal(result.files, null);
    assert.doesNotMatch(JSON.stringify(result), /synthetic-private/);
  }
  const badChecksum = tar(); badChecksum[20] ^= 1;
  const badHeader = tar(); badHeader[257] = 0;
  for (const [options, stage] of [
    [{ version: "not-a-version" }, "metadata-validation"],
    [{ stream: Buffer.concat([tar(), tar()]) }, "archive-framing"],
    [{ stream: badChecksum }, "archive-checksum"],
    [{ stream: badHeader }, "archive-header"],
    [{ stream: tar([...payload, ["../escape", "x"]]) }, "archive-path"],
    [{ stream: tar([...payload, ["usr/link", "", { type: "2", link: "bin/example" }]]) }, "archive-entry-type"],
    [{ stream: Buffer.concat([header("usr/huge", limits.file + 1), Buffer.alloc(1024)]) }, "archive-bounds"],
    [{ resources: { ...expected, application: "0".repeat(64) } }, "resource-application-hash"],
  ]) {
    const result = inspect(options);
    assert.equal(result.failureStage, stage);
    assert.equal(result.reason, "tool-or-payload-validation-failed");
    assert.equal(result.status, "unverified");
  }
  assert.equal(inspect().status, "payload-inspected");
  assert.equal(Object.hasOwn(inspect(), "failureStage"), false);
});

test("DEB resource diagnostics distinguish every predicate without exposing offending content", () => {
  const inspect = (files = payload, resources = expected) => {
    let call = 0;
    const values = ["locked-in-flow", "0.5.0-alpha.1", "amd64", "", ""];
    return inspectPackage("deb", "/synthetic/input.deb", packageBytes("deb"), resources, () => {
      const index = call++;
      return index < 5 ? Buffer.from(values[index] + "\n") : tar(files);
    });
  };
  const cases = [
    [payload.filter((_, i) => i !== 1), expected, "resource-model-count"],
    [[...payload, ["usr/extra/models/ggml-base.en.bin", payload[1][1]]], expected, "resource-model-count"],
    [payload, { ...expected, model: "0".repeat(64) }, "resource-model-hash"],
    [payload.slice(1), expected, "resource-application-missing"],
    [payload.map(([p, b], i) => [p, i === 0 ? Buffer.from("synthetic-not-elf") : b]), expected, "resource-application-format"],
    [payload, { ...expected, application: "0".repeat(64) }, "resource-application-hash"],
  ];
  for (let i = 2; i < 6; i++) {
    const label = payload[i][0].split("/").at(-1);
    cases.push(
      [payload.filter((_, index) => index !== i), expected, "resource-compliance-count"],
      [[...payload, ["usr/extra/compliance/" + label, payload[i][1]]], expected, "resource-compliance-count"],
      [payload.map(([p, b], index) => [index === i ? "usr/elsewhere/compliance/" + label : p, b]), expected, "resource-compliance-location"],
      [payload, { ...expected, [label]: "0".repeat(64) }, "resource-compliance-hash"],
    );
  }
  for (const [files, resources, stage] of cases) {
    const result = inspect(files, resources);
    assert.equal(result.failureStage, stage);
    assert.equal(result.status, "unverified");
    assert.equal(result.reason, "tool-or-payload-validation-failed");
    assert.equal(result.metadata, null);
    assert.equal(result.files, null);
    assert.deepEqual(Object.keys(result).sort(), ["format", "bytes", "sha256", "status", "licenseReview", "reason", "metadata", "files", "failureStage"].sort());
    assert.doesNotMatch(JSON.stringify(result), /synthetic|ggml|SBOM|MODEL|LICENSE|NOTICES|usr/);
  }
  assert.equal(inspect().status, "payload-inspected");
});
