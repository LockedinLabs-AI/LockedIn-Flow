import { createHash, randomUUID } from "node:crypto";
import {
  chmodSync,
  createReadStream,
  createWriteStream,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import https from "node:https";
import { homedir, hostname } from "node:os";
import path from "node:path";
import { Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

const IDENTIFIER = /^[A-Za-z0-9._-]+$/;
const SHA256 = /^[0-9a-f]{64}$/;
const REVISION = /^[0-9a-f]{40}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const REDIRECT_CODES = new Set([301, 302, 303, 307, 308]);
const PERMISSION_PROFILES = Object.freeze({
  user: Object.freeze({ directoryMode: 0o700, fileMode: 0o600 }),
  managed: Object.freeze({ directoryMode: 0o755, fileMode: 0o644 }),
});
const PROVISIONING_LOCK_NAME = ".lockedin-flow-provision.lock";
const TEMPORARY_ROOTS = Object.freeze([
  "/tmp",
  "/private/tmp",
  "/var/tmp",
  // /var is a system link to /private/var on macOS. Keep the canonical form
  // explicit so resolving the deepest existing ancestor cannot bypass policy.
  "/private/var/tmp",
]);

function isPathInside(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${path.sep}`);
}

function safeRelativePath(value) {
  if (!value || value.startsWith("/") || value.includes("\\") || value.includes("\0")) {
    return false;
  }
  return value.split("/").every((part) => part && part !== "." && part !== "..");
}

function parseInteger(value, label) {
  if (!/^(0|[1-9][0-9]*)$/.test(value)) throw new Error(`Invalid ${label}.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) throw new Error(`Unsafe ${label}.`);
  return parsed;
}

export function parseModelSources(text) {
  const sources = new Map();
  for (const rawLine of text.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const fields = line.split("\t");
    if (fields.length !== 4) throw new Error("Invalid model source manifest row.");
    const [folder, repository, revision, selection] = fields;
    const repositoryParts = repository.split("/");
    if (
      !IDENTIFIER.test(folder) ||
      folder === "." ||
      folder === ".." ||
      repositoryParts.length !== 2 ||
      !repositoryParts.every((part) => IDENTIFIER.test(part)) ||
      !REVISION.test(revision) ||
      !["default", "optional"].includes(selection) ||
      sources.has(folder)
    ) {
      throw new Error("Unsafe or duplicate model source manifest row.");
    }
    sources.set(folder, { folder, repository, revision, selection });
  }
  if (sources.size === 0) throw new Error("Model source manifest is empty.");
  return sources;
}

export function parseModelArtifacts(text, sources) {
  const artifacts = new Map([...sources.keys()].map((folder) => [folder, []]));
  const seenPaths = new Set();
  for (const rawLine of text.split(/\r?\n/u)) {
    if (!rawLine.trim() || rawLine.startsWith("#")) continue;
    const fields = rawLine.split("\t");
    if (fields.length !== 3) throw new Error("Invalid model artifact manifest row.");
    const [sha256, byteText, relativePath] = fields;
    if (!SHA256.test(sha256) || !safeRelativePath(relativePath) || seenPaths.has(relativePath)) {
      throw new Error("Unsafe or duplicate model artifact manifest row.");
    }
    const folder = relativePath.split("/", 1)[0];
    if (!sources.has(folder)) throw new Error(`Artifact has no pinned source: ${folder}`);
    const pathInsideModel = relativePath.slice(folder.length + 1);
    if (!safeRelativePath(pathInsideModel)) throw new Error("Artifact path has no model-relative part.");
    const byteCount = parseInteger(byteText, "artifact byte count");
    artifacts.get(folder).push({ sha256, byteCount, path: pathInsideModel });
    seenPaths.add(relativePath);
  }
  for (const [folder, files] of artifacts) {
    if (files.length === 0) throw new Error(`No artifacts listed for ${folder}.`);
  }
  return artifacts;
}

export function loadModelCatalog(repositoryRoot) {
  const sources = parseModelSources(
    readFileSync(path.join(repositoryRoot, "security", "model-sources.tsv"), "utf8"),
  );
  const artifacts = parseModelArtifacts(
    readFileSync(path.join(repositoryRoot, "security", "model-artifacts.tsv"), "utf8"),
    sources,
  );
  return { sources, artifacts };
}

export function isTrustedModelURL(value) {
  let url;
  try {
    url = value instanceof URL ? value : new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== "https:" || url.username || url.password) return false;
  const host = url.hostname.toLowerCase();
  return (
    host === "huggingface.co" ||
    host.endsWith(".huggingface.co") ||
    host === "hf.co" ||
    host.endsWith(".hf.co")
  );
}

function artifactURL(source, artifact) {
  const encodedPath = artifact.path.split("/").map(encodeURIComponent).join("/");
  const value = new URL(
    `/${source.repository}/resolve/${source.revision}/${encodedPath}`,
    "https://huggingface.co",
  );
  if (!isTrustedModelURL(value)) throw new Error("Could not construct a trusted model URL.");
  return value;
}

async function sha256File(file) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest("hex");
}

function inspectModelTree(root) {
  const directories = [{ absolute: root, relative: "" }];
  const files = [];
  function walk(directory, prefix) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      const absolute = path.join(directory, entry.name);
      const stat = lstatSync(absolute, { throwIfNoEntry: false });
      if (!stat) throw new Error("Model directory changed while it was being inspected.");
      if (stat.isSymbolicLink()) throw new Error("Model directory contains a symbolic link.");
      if (stat.isDirectory()) {
        directories.push({ absolute, relative });
        walk(absolute, relative);
      } else if (stat.isFile()) {
        files.push({ absolute, relative });
      } else {
        throw new Error("Model directory contains a special file.");
      }
    }
  }
  walk(root, "");
  return { directories, files };
}

function permissionModes(profile) {
  if (!Object.hasOwn(PERMISSION_PROFILES, profile)) {
    throw new Error(`Unknown model permission profile: ${profile}`);
  }
  return PERMISSION_PROFILES[profile];
}

export function validateModelDestination(value) {
  if (!path.isAbsolute(value)) throw new Error("Model destination must be absolute.");
  const normalized = path.resolve(value);
  const filesystemRoot = path.parse(normalized).root;
  if (normalized === filesystemRoot || path.basename(normalized) !== "Models") {
    throw new Error('Model destination must be a dedicated directory whose final component is "Models".');
  }

  const parent = path.dirname(normalized);
  const broadRoots = new Set([
    filesystemRoot,
    "/Applications",
    "/Library",
    "/System",
    "/Users",
    "/Volumes",
    "/bin",
    "/etc",
    "/opt",
    "/private",
    "/root",
    "/sbin",
    "/tmp",
    "/usr",
    "/var",
    "/var/root",
    homedir(),
  ]);
  const directUserHome = ["/Users", "/home"].some((root) => path.dirname(parent) === root);
  const forbiddenSystemTrees = ["/Applications", "/System", "/bin", "/etc", "/opt", "/sbin", "/usr"];
  const insideForbiddenSystemTree = forbiddenSystemTrees.some((root) =>
    isPathInside(root, normalized),
  );
  const insideTemporaryTree = TEMPORARY_ROOTS.some((root) => isPathInside(root, normalized));
  if (broadRoots.has(parent) || directUserHome || insideForbiddenSystemTree) {
    throw new Error("Model destination cannot be a filesystem, system, temporary, or home root.");
  }
  if (insideTemporaryTree) {
    throw new Error(
      "Model destination cannot be inside /tmp, /private/tmp, or /var/tmp. Use a durable staging directory ending in Models.",
    );
  }

  // Refuse user-controlled link aliases before mkdir/chmod. /var is a stable
  // macOS system alias and is resolved below; allowing it keeps normal macOS
  // paths usable without allowing a deeper link to redirect the destination.
  let current = filesystemRoot;
  let existingComponentCount = 0;
  const allowedSystemAliases = new Set(["/var"]);
  const components = normalized.slice(filesystemRoot.length).split(path.sep).filter(Boolean);
  for (const [index, component] of components.entries()) {
    current = path.join(current, component);
    const stat = lstatSync(current, { throwIfNoEntry: false });
    if (!stat) break;
    if (stat.isSymbolicLink() && !allowedSystemAliases.has(current)) {
      throw new Error("Model destination cannot traverse a symbolic link.");
    }
    if (!stat.isDirectory() && !stat.isSymbolicLink()) {
      throw new Error("Every existing model destination component must be a directory.");
    }
    existingComponentCount = index + 1;
  }

  // Resolve the deepest existing ancestor and append only the missing lexical
  // suffix. This catches canonical temporary/system aliases while never
  // resolving through a user-controlled symlink accepted by the walk above.
  const deepestExisting =
    existingComponentCount === 0
      ? filesystemRoot
      : path.join(filesystemRoot, ...components.slice(0, existingComponentCount));
  const resolved = path.resolve(
    realpathSync(deepestExisting),
    ...components.slice(existingComponentCount),
  );
  const resolvedParent = path.dirname(resolved);
  const resolvedInsideTemporaryTree = TEMPORARY_ROOTS.some((root) => isPathInside(root, resolved));
  const resolvedInsideForbiddenSystemTree = forbiddenSystemTrees.some((root) =>
    isPathInside(root, resolved),
  );
  if (resolvedInsideTemporaryTree) {
    throw new Error(
      "Model destination resolves inside /tmp, /private/tmp, or /var/tmp. Use a durable staging directory ending in Models.",
    );
  }
  if (broadRoots.has(resolvedParent) || resolvedInsideForbiddenSystemTree) {
    throw new Error("Model destination resolves to a filesystem or system location that is not allowed.");
  }
  return normalized;
}

function readProvisioningLock(lockPath) {
  const stat = lstatSync(lockPath, { throwIfNoEntry: false });
  if (!stat?.isFile() || stat.isSymbolicLink()) {
    throw new Error(
      `The ${PROVISIONING_LOCK_NAME} entry is not a regular file. Inspect it and remove it only after confirming no provisioner is running.`,
    );
  }
  let value;
  try {
    value = JSON.parse(readFileSync(lockPath, "utf8"));
  } catch {
    throw new Error(
      `The ${PROVISIONING_LOCK_NAME} file is invalid. Inspect it and remove it only after confirming no provisioner is running.`,
    );
  }
  if (
    value?.schema !== 1 ||
    !Number.isSafeInteger(value.pid) ||
    value.pid <= 0 ||
    typeof value.host !== "string" ||
    value.host.length === 0 ||
    !UUID.test(value.token ?? "") ||
    typeof value.createdAt !== "string" ||
    !Number.isFinite(Date.parse(value.createdAt))
  ) {
    throw new Error(
      `The ${PROVISIONING_LOCK_NAME} file has invalid ownership metadata. Inspect it and remove it only after confirming no provisioner is running.`,
    );
  }
  return value;
}

function processIsRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    // EPERM still means the process exists. Only ESRCH is proof that this
    // same-host owner is gone; PID reuse intentionally fails conservatively.
    return error?.code !== "ESRCH";
  }
}

export function acquireModelDestinationLock(destinationRoot) {
  const lockPath = path.join(destinationRoot, PROVISIONING_LOCK_NAME);
  const owner = {
    schema: 1,
    pid: process.pid,
    host: hostname(),
    token: randomUUID(),
    createdAt: new Date().toISOString(),
  };

  while (true) {
    try {
      writeFileSync(lockPath, `${JSON.stringify(owner)}\n`, { flag: "wx", mode: 0o600 });
      break;
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
      const existing = readProvisioningLock(lockPath);
      if (existing.host === owner.host && !processIsRunning(existing.pid)) {
        // Never remove by pathname here: two contenders could both classify an
        // old owner as stale and one could then unlink the other's new lock.
        // Manual removal after an operator confirms inactivity is conservative
        // and keeps stale recovery free of a check/unlink race.
        throw new Error(
          `The process recorded in ${PROVISIONING_LOCK_NAME} no longer exists. Confirm no provisioner is running, then remove the stale lock manually and retry.`,
        );
      }
      throw new Error(
        `Another model provisioner owns ${PROVISIONING_LOCK_NAME}. Wait for it to finish. If no provisioner is running, inspect the lock and remove it manually.`,
      );
    }
  }

  let released = false;
  return () => {
    if (released) return;
    const existing = lstatSync(lockPath, { throwIfNoEntry: false });
    if (!existing) {
      released = true;
      return;
    }
    const currentOwner = readProvisioningLock(lockPath);
    if (currentOwner.token !== owner.token) {
      throw new Error(
        `Provisioning completed, but ${PROVISIONING_LOCK_NAME} is now owned by another process and was not removed.`,
      );
    }
    unlinkSync(lockPath);
    released = true;
  };
}

function exactModelTree(folder, expectedArtifacts) {
  const rootStat = lstatSync(folder, { throwIfNoEntry: false });
  if (!rootStat?.isDirectory() || rootStat.isSymbolicLink()) {
    throw new Error("Model root must be a regular directory, not a symbolic link.");
  }
  const tree = inspectModelTree(folder);
  const actual = tree.files.map((entry) => entry.relative).sort();
  const expected = expectedArtifacts.map((artifact) => artifact.path).sort();
  if (actual.length !== expected.length || actual.some((value, index) => value !== expected[index])) {
    throw new Error("Model directory has missing or unexpected files.");
  }
  return tree;
}

export function verifyModelPermissions(folder, expectedArtifacts, profile = "user") {
  const modes = permissionModes(profile);
  const tree = exactModelTree(folder, expectedArtifacts);
  for (const entry of tree.directories) {
    const stat = lstatSync(entry.absolute, { throwIfNoEntry: false });
    if (!stat?.isDirectory() || stat.isSymbolicLink()) {
      throw new Error("Model directory changed while permissions were being verified.");
    }
    if ((stat.mode & 0o7777) !== modes.directoryMode) {
      throw new Error(`Model directory has unsafe permissions: ${entry.relative || "."}`);
    }
  }
  for (const entry of tree.files) {
    const stat = lstatSync(entry.absolute, { throwIfNoEntry: false });
    if (!stat?.isFile() || stat.isSymbolicLink()) {
      throw new Error("Model artifact changed while permissions were being verified.");
    }
    if ((stat.mode & 0o7777) !== modes.fileMode) {
      throw new Error(`Model artifact has unsafe permissions: ${entry.relative}`);
    }
  }
}

export function applyModelPermissions(folder, expectedArtifacts, profile = "user") {
  const modes = permissionModes(profile);
  const tree = exactModelTree(folder, expectedArtifacts);

  // Inspect the complete tree before changing anything, then lstat every path
  // again immediately before chmod so links and special files are never
  // intentionally followed by the permission-normalization step.
  for (const entry of tree.files) {
    const stat = lstatSync(entry.absolute, { throwIfNoEntry: false });
    if (!stat?.isFile() || stat.isSymbolicLink()) {
      throw new Error("Model artifact changed while permissions were being applied.");
    }
    chmodSync(entry.absolute, modes.fileMode);
  }
  const deepestDirectoriesFirst = [...tree.directories].sort(
    (left, right) => right.absolute.length - left.absolute.length,
  );
  for (const entry of deepestDirectoriesFirst) {
    const stat = lstatSync(entry.absolute, { throwIfNoEntry: false });
    if (!stat?.isDirectory() || stat.isSymbolicLink()) {
      throw new Error("Model directory changed while permissions were being applied.");
    }
    chmodSync(entry.absolute, modes.directoryMode);
  }
  verifyModelPermissions(folder, expectedArtifacts, profile);
}

function transactionEntries(destinationRoot, folder, kind) {
  const prefix = `.${kind}-${folder}-`;
  return readdirSync(destinationRoot, { withFileTypes: true })
    .filter((entry) => entry.name.startsWith(prefix) && UUID.test(entry.name.slice(prefix.length)))
    .map((entry) => ({ entry, path: path.join(destinationRoot, entry.name) }));
}

function removeTransactionEntry(item) {
  rmSync(item.path, {
    recursive: item.entry.isDirectory() && !item.entry.isSymbolicLink(),
    force: true,
  });
}

export async function verifyModelFolder(folder, expectedArtifacts) {
  exactModelTree(folder, expectedArtifacts);
  for (const artifact of expectedArtifacts) {
    const file = path.join(folder, ...artifact.path.split("/"));
    const stat = statSync(file, { throwIfNoEntry: false });
    if (!stat?.isFile() || stat.size !== artifact.byteCount) {
      throw new Error(`Model artifact size mismatch: ${artifact.path}`);
    }
    if ((await sha256File(file)) !== artifact.sha256) {
      throw new Error(`Model artifact hash mismatch: ${artifact.path}`);
    }
  }
}

export async function recoverInterruptedModelTransaction(
  destinationRoot,
  folder,
  expectedArtifacts,
) {
  const finalDirectory = path.join(destinationRoot, folder);
  const displaced = transactionEntries(destinationRoot, folder, "replaced");
  if (displaced.length > 1) {
    throw new Error(`Multiple interrupted repair backups exist for ${folder}; review them manually.`);
  }

  if (displaced.length === 1) {
    if (existsSync(finalDirectory)) {
      try {
        await verifyModelFolder(finalDirectory, expectedArtifacts);
      } catch {
        throw new Error(
          `An interrupted repair left both an invalid active model and a backup for ${folder}; review them manually.`,
        );
      }
      removeTransactionEntry(displaced[0]);
      console.warn(`Removed an obsolete repair backup after verifying ${folder}.`);
    } else {
      renameSync(displaced[0].path, finalDirectory);
      console.warn(`Restored the previous ${folder} directory after an interrupted repair.`);
    }
  }

  const stagingEntries = transactionEntries(destinationRoot, folder, "provision");
  for (const item of stagingEntries) removeTransactionEntry(item);
  if (stagingEntries.length > 0) {
    console.warn(`Removed ${stagingEntries.length} incomplete ${folder} staging director${stagingEntries.length === 1 ? "y" : "ies"}.`);
  }
}

function responseFor(url, redirectsRemaining) {
  return new Promise((resolve, reject) => {
    if (!isTrustedModelURL(url)) {
      reject(new Error("Model download attempted to use an untrusted URL."));
      return;
    }
    const request = https.get(
      url,
      {
        headers: { "User-Agent": "LockedIn-Flow-Provisioner/0.4.17" },
        timeout: 60_000,
      },
      (response) => {
        const status = response.statusCode ?? 0;
        if (REDIRECT_CODES.has(status)) {
          const location = response.headers.location;
          response.resume();
          if (!location || redirectsRemaining <= 0) {
            reject(new Error("Model download exceeded the redirect limit."));
            return;
          }
          let redirected;
          try {
            redirected = new URL(location, url);
          } catch {
            reject(new Error("Model host returned an invalid redirect URL."));
            return;
          }
          if (!isTrustedModelURL(redirected)) {
            reject(new Error("Model download redirected outside the trusted host boundary."));
            return;
          }
          responseFor(redirected, redirectsRemaining - 1).then(resolve, reject);
          return;
        }
        if (status !== 200) {
          response.resume();
          reject(new Error(`Model host returned HTTP ${status}.`));
          return;
        }
        resolve(response);
      },
    );
    request.on("timeout", () => request.destroy(new Error("Model download timed out.")));
    request.on("error", reject);
  });
}

async function downloadArtifact(source, artifact, destination) {
  const response = await responseFor(artifactURL(source, artifact), 5);
  const declaredLength = response.headers["content-length"];
  if (declaredLength !== undefined && parseInteger(declaredLength, "content length") !== artifact.byteCount) {
    response.destroy();
    throw new Error(`Unexpected content length for ${artifact.path}.`);
  }

  mkdirSync(path.dirname(destination), { recursive: true, mode: 0o700 });
  const hash = createHash("sha256");
  let received = 0;
  const limiter = new Transform({
    transform(chunk, _encoding, callback) {
      received += chunk.length;
      if (received > artifact.byteCount) {
        callback(new Error(`Download exceeded the pinned size for ${artifact.path}.`));
        return;
      }
      hash.update(chunk);
      callback(null, chunk);
    },
  });
  await pipeline(response, limiter, createWriteStream(destination, { flags: "wx", mode: 0o600 }));
  if (received !== artifact.byteCount || hash.digest("hex") !== artifact.sha256) {
    throw new Error(`Downloaded model artifact failed verification: ${artifact.path}`);
  }
}

async function downloadArtifactWithRetries(source, artifact, destination) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    rmSync(destination, { force: true });
    try {
      await downloadArtifact(source, artifact, destination);
      return;
    } catch (error) {
      lastError = error;
      rmSync(destination, { force: true });
      if (attempt < 3) {
        console.warn(`  Transfer interrupted; retrying (${attempt}/3)…`);
        await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
      }
    }
  }
  throw lastError;
}

export function selectedModelFolders(sources, includeOptional = false) {
  return [...sources.values()]
    .filter((source) => includeOptional || source.selection === "default")
    .map((source) => source.folder);
}

export async function provisionModels({
  repositoryRoot,
  destinationRoot,
  includeOptional = false,
  repairInvalid = false,
  permissionProfile = "user",
}) {
  destinationRoot = validateModelDestination(destinationRoot);
  const modes = permissionModes(permissionProfile);
  const { sources, artifacts } = loadModelCatalog(repositoryRoot);
  const selected = selectedModelFolders(sources, includeOptional);
  mkdirSync(destinationRoot, { recursive: true, mode: modes.directoryMode });
  const destinationStat = lstatSync(destinationRoot, { throwIfNoEntry: false });
  if (!destinationStat?.isDirectory() || destinationStat.isSymbolicLink()) {
    throw new Error("Model destination must be a regular directory, not a symbolic link.");
  }
  // Re-run the complete path policy after creation so a changed or newly
  // introduced ancestor is rejected before permissions or model state change.
  destinationRoot = validateModelDestination(destinationRoot);
  const releaseDestinationLock = acquireModelDestinationLock(destinationRoot);
  let provisioningFailed = false;
  try {
    chmodSync(destinationRoot, modes.directoryMode);

    // Recover transactions for the full reviewed catalog, not only today's
    // selection. A normal default run must also clean up an interrupted repair
    // of the optional model. The destination lock remains held through all
    // recovery, staging, activation, verification, and cleanup.
    for (const [folder, expectedArtifacts] of artifacts) {
      await recoverInterruptedModelTransaction(destinationRoot, folder, expectedArtifacts);
    }

    for (const folder of selected) {
      const finalDirectory = path.join(destinationRoot, folder);
      const source = sources.get(folder);
      const expectedArtifacts = artifacts.get(folder);
      let replaceExisting = false;
      if (existsSync(finalDirectory)) {
        try {
          await verifyModelFolder(finalDirectory, expectedArtifacts);
        } catch (error) {
          if (!repairInvalid) {
            throw new Error(
              `Existing model ${folder} failed verification. Re-run with --repair to stage and atomically replace it. ${error instanceof Error ? error.message : String(error)}`,
            );
          }
          replaceExisting = true;
          console.warn(`Existing model failed verification; staging a replacement: ${folder}`);
        }
        if (!replaceExisting) {
          applyModelPermissions(finalDirectory, expectedArtifacts, permissionProfile);
          console.log(`Verified existing model: ${folder}`);
          continue;
        }
      }

      const staging = path.join(destinationRoot, `.provision-${folder}-${randomUUID()}`);
      mkdirSync(staging, { recursive: false, mode: 0o700 });
      try {
        console.log(`Provisioning ${folder} (${expectedArtifacts.length} pinned files)…`);
        for (const artifact of expectedArtifacts) {
          const mebibytes = (artifact.byteCount / (1_024 * 1_024)).toFixed(1);
          console.log(`  ${artifact.path} (${mebibytes} MiB)`);
          await downloadArtifactWithRetries(
            source,
            artifact,
            path.join(staging, ...artifact.path.split("/")),
          );
        }
        await verifyModelFolder(staging, expectedArtifacts);
        applyModelPermissions(staging, expectedArtifacts, permissionProfile);
        if (!replaceExisting) {
          renameSync(staging, finalDirectory);
        } else {
          const displaced = path.join(destinationRoot, `.replaced-${folder}-${randomUUID()}`);
          renameSync(finalDirectory, displaced);
          let activated = false;
          try {
            renameSync(staging, finalDirectory);
            activated = true;
            await verifyModelFolder(finalDirectory, expectedArtifacts);
            verifyModelPermissions(finalDirectory, expectedArtifacts, permissionProfile);
          } catch (error) {
            if (activated && existsSync(finalDirectory)) {
              rmSync(finalDirectory, { recursive: true, force: true });
            }
            if (!existsSync(finalDirectory) && existsSync(displaced)) {
              renameSync(displaced, finalDirectory);
            }
            throw error;
          }
          rmSync(displaced, { recursive: true, force: true });
        }
        console.log(`Verified and installed model: ${folder}`);
      } finally {
        if (existsSync(staging)) rmSync(staging, { recursive: true, force: true });
      }
    }
    return selected;
  } catch (error) {
    provisioningFailed = true;
    throw error;
  } finally {
    try {
      releaseDestinationLock();
    } catch (error) {
      const message = `Provisioning lock cleanup needs attention: ${error instanceof Error ? error.message : String(error)}`;
      if (!provisioningFailed) throw new Error(message);
      console.warn(message);
    }
  }
}
