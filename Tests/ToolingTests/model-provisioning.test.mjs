import { createHash, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir, hostname, tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import {
  applyModelPermissions,
  isTrustedModelURL,
  loadModelCatalog,
  parseModelArtifacts,
  parseModelSources,
  provisionModels,
  recoverInterruptedModelTransaction,
  selectedModelFolders,
  validateModelDestination,
  verifyModelFolder,
  verifyModelPermissions,
} from "../../scripts/lib/model-provisioning.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

test("reviewed manifests describe three models and 39 exact artifacts", () => {
  const { sources, artifacts } = loadModelCatalog(repositoryRoot);
  assert.equal(sources.size, 3);
  assert.equal([...artifacts.values()].flat().length, 39);
  assert.deepEqual(selectedModelFolders(sources), ["parakeet-tdt-0.6b-v3", "silero-vad"]);
  assert.equal(selectedModelFolders(sources, true).length, 3);
});

test("model host boundary rejects credentials, HTTP, and lookalike domains", () => {
  assert.equal(isTrustedModelURL("https://huggingface.co/a"), true);
  assert.equal(isTrustedModelURL("https://cdn-lfs.hf.co/a"), true);
  assert.equal(isTrustedModelURL("https://cas-bridge.xethub.hf.co/a"), true);
  assert.equal(isTrustedModelURL("http://huggingface.co/a"), false);
  assert.equal(isTrustedModelURL("https://example.com/a"), false);
  assert.equal(isTrustedModelURL("https://huggingface.co.example.com/a"), false);
  const credentialURL = new URL("https://huggingface.co/a");
  credentialURL.username = "synthetic-user";
  credentialURL.password = "synthetic-password";
  assert.equal(isTrustedModelURL(credentialURL), false);
});

test("managed provisioning is explicit and requires a destination", () => {
  const command = path.join(repositoryRoot, "scripts", "provision-models.mjs");
  const help = spawnSync(process.execPath, [command, "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /--managed/);
  assert.match(help.stdout, /0755 directories and\s+0644 files/);

  const missingDestination = spawnSync(process.execPath, [command, "--managed"], {
    encoding: "utf8",
  });
  assert.equal(missingDestination.status, 64);
  assert.match(missingDestination.stderr, /requires an explicit absolute --destination/);
});

test("unsafe model destinations fail before any permission change", async () => {
  for (const unsafe of [
    "/",
    "/Library",
    "/Library/Models",
    "/System/Library/Models",
    path.join(homedir(), "Models"),
    "/tmp/lockedin-flow/Models",
    "/private/tmp/lockedin-flow/Models",
    "/var/tmp/lockedin-flow/Models",
  ]) {
    assert.throws(() => validateModelDestination(unsafe), /Model destination/);
  }

  const root = mkdtempSync(path.join(tmpdir(), "lockedin-unsafe-model-destination-test-"));
  try {
    chmodSync(root, 0o750);
    await assert.rejects(
      () =>
        provisionModels({
          repositoryRoot: path.join(root, "missing-repository"),
          destinationRoot: root,
          permissionProfile: "managed",
        }),
      /final component is "Models"/,
    );
    assert.equal(statSync(root).mode & 0o777, 0o750);

    const realParent = path.join(root, "real-parent");
    const linkedParent = path.join(root, "linked-parent");
    mkdirSync(realParent);
    symlinkSync(realParent, linkedParent);
    assert.throws(
      () => validateModelDestination(path.join(linkedParent, "staged", "Models")),
      /symbolic link/,
    );
    assert.equal(existsSync(path.join(realParent, "staged")), false);

    const nonDirectory = path.join(root, "not-a-directory");
    writeFileSync(nonDirectory, "not a directory");
    assert.throws(
      () => validateModelDestination(path.join(nonDirectory, "staged", "Models")),
      /must be a directory/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("unsafe and unpinned manifest rows fail closed", () => {
  assert.throws(
    () => parseModelSources("../model\tOrg/repo\t0123456789012345678901234567890123456789\tdefault"),
    /Unsafe/,
  );
  const sources = parseModelSources(
    "model\tOrg/repo\t0123456789012345678901234567890123456789\tdefault",
  );
  assert.throws(
    () => parseModelArtifacts(`${"a".repeat(64)}\t1\tmodel/../escape`, sources),
    /Unsafe/,
  );
});

test("local verifier accepts only the exact regular-file tree", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-test-"));
  try {
    const contents = Buffer.from("synthetic model fixture", "utf8");
    const hash = createHash("sha256").update(contents).digest("hex");
    mkdirSync(path.join(root, "nested"));
    writeFileSync(path.join(root, "nested", "model.bin"), contents);
    const artifacts = [{ path: "nested/model.bin", byteCount: contents.length, sha256: hash }];
    await verifyModelFolder(root, artifacts);

    writeFileSync(path.join(root, "unexpected"), "not allowed");
    await assert.rejects(() => verifyModelFolder(root, artifacts), /missing or unexpected/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("local verifier rejects a symbolic-link model root", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-link-test-"));
  try {
    const real = path.join(root, "real");
    const link = path.join(root, "link");
    mkdirSync(real);
    symlinkSync(real, link);
    await assert.rejects(() => verifyModelFolder(link, []), /symbolic link/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("model permission profiles keep user caches private and managed caches readable", () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-permissions-test-"));
  try {
    const model = path.join(root, "model");
    const nested = path.join(model, "nested");
    const artifact = path.join(nested, "model.bin");
    const expected = [{ path: "nested/model.bin" }];
    mkdirSync(nested, { recursive: true, mode: 0o700 });
    writeFileSync(artifact, "model", { mode: 0o600 });

    assert.throws(
      () => verifyModelPermissions(model, expected, "managed"),
      /unsafe permissions/,
    );
    applyModelPermissions(model, expected, "managed");
    verifyModelPermissions(model, expected, "managed");
    assert.equal(statSync(model).mode & 0o777, 0o755);
    assert.equal(statSync(nested).mode & 0o777, 0o755);
    assert.equal(statSync(artifact).mode & 0o777, 0o644);

    applyModelPermissions(model, expected, "user");
    verifyModelPermissions(model, expected, "user");
    assert.equal(statSync(model).mode & 0o777, 0o700);
    assert.equal(statSync(nested).mode & 0o777, 0o700);
    assert.equal(statSync(artifact).mode & 0o777, 0o600);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("provisioning applies the selected permission profile to an existing verified tree", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-provision-permissions-test-"));
  try {
    const repository = path.join(root, "repository");
    const security = path.join(repository, "security");
    const destination = path.join(root, "Models");
    const model = path.join(destination, "synthetic-model");
    const nested = path.join(model, "nested");
    const artifact = path.join(nested, "model.bin");
    const contents = Buffer.from("verified model", "utf8");
    const hash = createHash("sha256").update(contents).digest("hex");
    mkdirSync(security, { recursive: true });
    mkdirSync(nested, { recursive: true, mode: 0o700 });
    writeFileSync(
      path.join(security, "model-sources.tsv"),
      `synthetic-model\tExample/model\t${"0".repeat(40)}\tdefault\n`,
    );
    writeFileSync(
      path.join(security, "model-artifacts.tsv"),
      `${hash}\t${contents.length}\tsynthetic-model/nested/model.bin\n`,
    );
    writeFileSync(artifact, contents, { mode: 0o600 });

    await provisionModels({
      repositoryRoot: repository,
      destinationRoot: destination,
      permissionProfile: "managed",
    });
    assert.equal(statSync(destination).mode & 0o777, 0o755);
    assert.equal(statSync(model).mode & 0o777, 0o755);
    assert.equal(statSync(nested).mode & 0o777, 0o755);
    assert.equal(statSync(artifact).mode & 0o777, 0o644);

    await provisionModels({ repositoryRoot: repository, destinationRoot: destination });
    assert.equal(statSync(destination).mode & 0o777, 0o700);
    assert.equal(statSync(model).mode & 0o777, 0o700);
    assert.equal(statSync(nested).mode & 0o777, 0o700);
    assert.equal(statSync(artifact).mode & 0o777, 0o600);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("permission normalization rejects links and special files before chmod", () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-permission-safety-test-"));
  try {
    const linkedModel = path.join(root, "linked-model");
    const linkedArtifact = path.join(linkedModel, "model.bin");
    mkdirSync(linkedModel, { mode: 0o700 });
    writeFileSync(linkedArtifact, "model", { mode: 0o600 });
    symlinkSync(linkedArtifact, path.join(linkedModel, "unexpected-link"));
    assert.throws(
      () => applyModelPermissions(linkedModel, [{ path: "model.bin" }], "managed"),
      /symbolic link/,
    );
    assert.equal(statSync(linkedModel).mode & 0o777, 0o700);
    assert.equal(statSync(linkedArtifact).mode & 0o777, 0o600);

    const specialModel = path.join(root, "special-model");
    const specialArtifact = path.join(specialModel, "model.bin");
    mkdirSync(specialModel, { mode: 0o700 });
    writeFileSync(specialArtifact, "model", { mode: 0o600 });
    const fifo = path.join(specialModel, "unexpected-fifo");
    const mkfifo = spawnSync("/usr/bin/mkfifo", [fifo], { encoding: "utf8" });
    assert.equal(mkfifo.status, 0, mkfifo.stderr);
    assert.throws(
      () => applyModelPermissions(specialModel, [{ path: "model.bin" }], "managed"),
      /special file/,
    );
    assert.equal(statSync(specialModel).mode & 0o777, 0o700);
    assert.equal(statSync(specialArtifact).mode & 0o777, 0o600);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("transaction recovery removes stale staging and restores a displaced model", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-recovery-test-"));
  try {
    const folder = "synthetic-model";
    const displaced = path.join(root, `.replaced-${folder}-${randomUUID()}`);
    const staging = path.join(root, `.provision-${folder}-${randomUUID()}`);
    mkdirSync(displaced);
    mkdirSync(staging);
    writeFileSync(path.join(displaced, "old.bin"), "old model");
    writeFileSync(path.join(staging, "partial.bin"), "partial model");

    await recoverInterruptedModelTransaction(root, folder, []);

    assert.equal(existsSync(displaced), false);
    assert.equal(existsSync(staging), false);
    assert.equal(existsSync(path.join(root, folder, "old.bin")), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("transaction recovery keeps a verified activation and removes its old backup", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-activation-test-"));
  try {
    const folder = "synthetic-model";
    const active = path.join(root, folder);
    const displaced = path.join(root, `.replaced-${folder}-${randomUUID()}`);
    const contents = Buffer.from("verified model", "utf8");
    const artifacts = [
      {
        path: "model.bin",
        byteCount: contents.length,
        sha256: createHash("sha256").update(contents).digest("hex"),
      },
    ];
    mkdirSync(active);
    mkdirSync(displaced);
    writeFileSync(path.join(active, "model.bin"), contents);
    writeFileSync(path.join(displaced, "old.bin"), "invalid old model");

    await recoverInterruptedModelTransaction(root, folder, artifacts);

    assert.equal(existsSync(active), true);
    assert.equal(existsSync(displaced), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("concurrent provisioning serializes the complete destination transaction", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-concurrency-test-"));
  try {
    const repository = path.join(root, "repository");
    const security = path.join(repository, "security");
    const destination = path.join(root, "Models");
    const model = path.join(destination, "synthetic-model");
    const contents = Buffer.from("verified concurrent model", "utf8");
    const hash = createHash("sha256").update(contents).digest("hex");
    mkdirSync(security, { recursive: true });
    mkdirSync(model, { recursive: true });
    writeFileSync(
      path.join(security, "model-sources.tsv"),
      `synthetic-model\tExample/model\t${"0".repeat(40)}\tdefault\n`,
    );
    writeFileSync(
      path.join(security, "model-artifacts.tsv"),
      `${hash}\t${contents.length}\tsynthetic-model/model.bin\n`,
    );
    writeFileSync(path.join(model, "model.bin"), contents);

    const first = provisionModels({ repositoryRoot: repository, destinationRoot: destination });
    const second = provisionModels({ repositoryRoot: repository, destinationRoot: destination });
    const [firstResult, secondResult] = await Promise.allSettled([first, second]);

    assert.equal(firstResult.status, "fulfilled");
    assert.equal(secondResult.status, "rejected");
    assert.match(secondResult.reason.message, /Another model provisioner owns/);
    assert.equal(existsSync(path.join(destination, ".lockedin-flow-provision.lock")), false);
    await verifyModelFolder(model, [
      { path: "model.bin", byteCount: contents.length, sha256: hash },
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("lock cleanup survives failure and stale locks fail closed without racing", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "lockedin-model-lock-recovery-test-"));
  try {
    const repository = path.join(root, "repository");
    const security = path.join(repository, "security");
    const destination = path.join(root, "Models");
    const model = path.join(destination, "synthetic-model");
    const lock = path.join(destination, ".lockedin-flow-provision.lock");
    const expected = Buffer.from("expected", "utf8");
    mkdirSync(security, { recursive: true });
    mkdirSync(model, { recursive: true });
    writeFileSync(
      path.join(security, "model-sources.tsv"),
      `synthetic-model\tExample/model\t${"0".repeat(40)}\tdefault\n`,
    );
    writeFileSync(
      path.join(security, "model-artifacts.tsv"),
      `${createHash("sha256").update(expected).digest("hex")}\t${expected.length}\tsynthetic-model/model.bin\n`,
    );
    writeFileSync(path.join(model, "model.bin"), "invalid");

    await assert.rejects(
      () => provisionModels({ repositoryRoot: repository, destinationRoot: destination }),
      /failed verification/,
    );
    assert.equal(existsSync(lock), false);

    const exited = spawnSync(process.execPath, ["-e", ""], { encoding: "utf8" });
    assert.equal(exited.status, 0, exited.stderr);
    writeFileSync(
      lock,
      `${JSON.stringify({
        schema: 1,
        pid: exited.pid,
        host: hostname(),
        token: randomUUID(),
        createdAt: new Date().toISOString(),
      })}\n`,
    );
    await assert.rejects(
      () => provisionModels({ repositoryRoot: repository, destinationRoot: destination }),
      /recorded.*no longer exists.*remove the stale lock manually/,
    );
    assert.equal(existsSync(lock), true);

    rmSync(lock, { force: true });
    writeFileSync(lock, "{}\n");
    await assert.rejects(
      () => provisionModels({ repositoryRoot: repository, destinationRoot: destination }),
      /invalid ownership metadata.*confirming no provisioner is running/,
    );
    assert.equal(existsSync(lock), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
