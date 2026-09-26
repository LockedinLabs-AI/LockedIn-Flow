import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function fixture(t) {
  const directory = mkdtempSync(path.join(tmpdir(), "flow-publication-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const environment = {
    ...process.env,
    GIT_AUTHOR_NAME: "Synthetic Contributor",
    GIT_COMMITTER_NAME: "Synthetic Contributor",
    GIT_AUTHOR_EMAIL: "contributor@example.com",
    GIT_COMMITTER_EMAIL: "contributor@example.com",
  };
  const git = (...args) => {
    const result = spawnSync("git", args, { cwd: directory, env: environment, encoding: "utf8" });
    assert.equal(result.status, 0, "Synthetic repository operation failed");
    return result.stdout.trim();
  };
  const write = (file, text) => {
    mkdirSync(path.dirname(path.join(directory, file)), { recursive: true });
    writeFileSync(path.join(directory, file), text);
  };
  for (const file of ["scripts/check-public-content.mjs", "scripts/lib/public-content-policy.mjs"]) {
    write(file, readFileSync(path.join(root, file)));
  }
  write("security/public-media.json", JSON.stringify({ assets: {} }));
  write("README.md", "# Synthetic project\nA public test fixture.\n");
  git("init", "--initial-branch=main");
  const commit = () => {
    git("add", "-A");
    git("-c", "commit.gpgsign=false", "commit", "-m", "Synthetic test change");
  };
  const check = (...args) => spawnSync(process.execPath, ["scripts/check-public-content.mjs", ...args], {
    cwd: directory, encoding: "utf8",
  });
  commit();
  return { directory, git, write, commit, check };
}

test("history review rejects private material even after it was deleted", (t) => {
  const repo = fixture(t);
  assert.equal(repo.check("--history").status, 0);
  repo.write("docs/internal/notes.md", "synthetic confidential content that must stay out of logs");
  repo.commit();
  repo.git("rm", "docs/internal/notes.md");
  repo.commit();
  assert.equal(repo.check().status, 0);
  const result = repo.check("--history");
  assert.equal(result.status, 1);
  assert.match(result.stderr, /private-or-generated-material/);
  assert.doesNotMatch(result.stderr, /synthetic confidential content/);
  assert.doesNotMatch(result.stderr, /docs\/internal\/notes/);
});

test("publication review rejects shallow history and symlinked content", (t) => {
  const repo = fixture(t);
  symlinkSync("README.md", path.join(repo.directory, "SUPPORT.md"));
  assert.match(repo.check().stderr, /nonregular-git-entry/);
  repo.write(".git/shallow", `${repo.git("rev-parse", "HEAD")}\n`);
  assert.equal(repo.check("--history").status, 1);
});

test("publication review rejects missing documentation targets", (t) => {
  const repo = fixture(t);
  repo.write("README.md", "[Missing guide](docs/missing.md)\n");
  assert.match(repo.check().stderr, /broken-or-external-local-link/);
});
