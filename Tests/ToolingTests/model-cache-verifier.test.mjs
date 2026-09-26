import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const verifier = path.join(repositoryRoot, "scripts", "verify-model-cache.sh");
const aclVerifier = path.join(repositoryRoot, "scripts", "lib", "macos-acl.sh");

test("model verifier separates user-owned package staging from installed system checks", () => {
  const fixture = mkdtempSync(path.join(tmpdir(), "lockedin-model-verifier-test-"));
  try {
    const scripts = path.join(fixture, "scripts");
    const scriptLibrary = path.join(scripts, "lib");
    const security = path.join(fixture, "security");
    const models = path.join(fixture, "Models");
    const model = path.join(models, "synthetic-model");
    const artifact = path.join(model, "model.bin");
    const contents = Buffer.from("synthetic verifier fixture", "utf8");
    const hash = createHash("sha256").update(contents).digest("hex");
    mkdirSync(scripts);
    mkdirSync(scriptLibrary);
    mkdirSync(security);
    mkdirSync(model, { recursive: true, mode: 0o755 });
    copyFileSync(verifier, path.join(scripts, "verify-model-cache.sh"));
    copyFileSync(aclVerifier, path.join(scriptLibrary, "macos-acl.sh"));
    chmodSync(path.join(scripts, "verify-model-cache.sh"), 0o755);
    writeFileSync(
      path.join(security, "model-artifacts.tsv"),
      `${hash}\t${contents.length}\tsynthetic-model/model.bin\n`,
    );
    writeFileSync(artifact, contents, { mode: 0o644 });
    chmodSync(models, 0o755);
    chmodSync(model, 0o755);
    chmodSync(artifact, 0o644);

    assert.notEqual(statSync(models).uid, 0, "the staging fixture must be user-owned");
    const staging = spawnSync(
      path.join(scripts, "verify-model-cache.sh"),
      ["--managed", "--all", models],
      { encoding: "utf8" },
    );
    assert.equal(staging.status, 0, staging.stderr);
    assert.match(staging.stdout, /managed staging 0755\/0644 permissions/);

    const addStagingACL = spawnSync(
      "/bin/chmod",
      ["+a", "everyone allow write", artifact],
      { encoding: "utf8" },
    );
    assert.equal(addStagingACL.status, 0, addStagingACL.stderr);
    const stagingWithACL = spawnSync(
      path.join(scripts, "verify-model-cache.sh"),
      ["--managed", "--all", models],
      { encoding: "utf8" },
    );
    assert.equal(stagingWithACL.status, 0, stagingWithACL.stderr);
    spawnSync("/bin/chmod", ["-N", artifact], { encoding: "utf8" });

    const installed = spawnSync(
      path.join(scripts, "verify-model-cache.sh"),
      ["--managed-installed", "--all", models],
      { encoding: "utf8" },
    );
    assert.equal(installed.status, 1);
    assert.match(installed.stderr, /restricted to \/Library\/Application Support\/LockedIn Flow\/Models/);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("managed ACL verifier rejects real macOS ACL entries", () => {
  const fixture = mkdtempSync(path.join(tmpdir(), "lockedin-model-acl-test-"));
  try {
    const noACL = spawnSync("/bin/bash", [aclVerifier, fixture], { encoding: "utf8" });
    assert.equal(noACL.status, 0, noACL.stderr);

    const addACL = spawnSync("/bin/chmod", ["+a", "everyone allow write", fixture], {
      encoding: "utf8",
    });
    assert.equal(addACL.status, 0, addACL.stderr);

    const withACL = spawnSync("/bin/bash", [aclVerifier, fixture], { encoding: "utf8" });
    assert.equal(withACL.status, 1);
    assert.match(withACL.stderr, /must not have extended ACL entries/);
  } finally {
    spawnSync("/bin/chmod", ["-N", fixture], { encoding: "utf8" });
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("installed and staging managed verification modes cannot be combined", () => {
  const result = spawnSync(
    verifier,
    ["--managed", "--managed-installed", "/Library/Application Support/LockedIn Flow/Models"],
    { encoding: "utf8" },
  );

  assert.equal(result.status, 64);
  assert.match(result.stderr, /mutually exclusive/);
});

test("model verifier documents post-install ownership verification", () => {
  const result = spawnSync(verifier, ["--help"], { encoding: "utf8" });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /--managed-installed/);
  assert.match(result.stdout, /root:wheel system tree/);
  assert.match(result.stdout, /ACL/);
  assert.match(result.stdout, /ownership may remain with the build user/);
});
