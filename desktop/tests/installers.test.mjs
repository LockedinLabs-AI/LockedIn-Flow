import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const environment = { ...process.env };
delete environment.GITHUB_ACTIONS;
delete environment.RUNNER_OS;
delete environment.RUNNER_ENVIRONMENT;

test("destructive Linux package checks refuse a normal local environment", () => {
  const result = spawnSync("bash", ["scripts/test-linux-package.sh"], {
    cwd: root, encoding: "utf8", env: environment,
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /restricted to an ephemeral Linux CI runner/);
});

test("destructive Windows package checks refuse a normal local environment", {
  skip: process.platform !== "win32",
}, () => {
  const result = spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-File", "scripts/test-windows-installers.ps1"], {
    cwd: root, encoding: "utf8", env: environment,
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /restricted to an ephemeral Windows CI runner/);
});

test("installer workflow exercises both Windows formats and Linux removal", () => {
  const windows = readFileSync(path.join(root, "scripts/test-windows-installers.ps1"), "utf8");
  const linux = readFileSync(path.join(root, "scripts/test-linux-package.sh"), "utf8");
  const workflow = readFileSync(path.join(root, "../.github/workflows/desktop.yml"), "utf8");
  for (const name of ["test-windows-installers.ps1", "test-linux-package.sh"])
    assert.ok(workflow.includes(name));
  assert.match(windows, /\/i .*\/qn \/norestart INSTALLDIR=/);
  assert.match(windows, /\/x .*\/qn \/norestart/);
  assert.match(windows, /Assert-Payload \$msiDirectory/);
  assert.match(windows, /Assert-Removed \$msiDirectory/);
  assert.match(windows, /Assert-Removed \$nsisDirectory/);
  assert.match(linux, /sudo dpkg --install/);
  assert.match(linux, /sudo dpkg --remove/);
  assert.match(linux, /cmp --/);
});
