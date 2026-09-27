#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { rustHost } from "./build-platform.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const run = (command, args) =>
  execFileSync(command, args, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const host = rustHost(run("rustc", ["-vV"]));
const target = process.argv[2] ?? host;
if (!target || !/^[-a-z0-9_]+$/.test(target))
  throw new Error("A Rust target triple is required.");
const metadata = JSON.parse(
  run("cargo", [
    "metadata",
    "--format-version",
    "1",
    "--locked",
    "--all-features",
    "--filter-platform",
    target,
  ]),
);
const nodes = new Map(metadata.resolve.nodes.map((node) => [node.id, node]));
const packages = metadata.packages
  .filter((pkg) => nodes.has(pkg.id))
  .sort((a, b) =>
    `${a.name}@${a.version}`.localeCompare(`${b.name}@${b.version}`),
  );
const reference = (pkg) => `pkg:cargo/${pkg.name}@${pkg.version}`;
const references = new Map(packages.map((pkg) => [pkg.id, reference(pkg)]));
const lock = await readFile(path.join(root, "Cargo.lock"), "utf8");
const checksums = new Map(
  [
    ...lock.matchAll(
      /\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"(?:\nsource = "[^"]+")?\nchecksum = "([a-f0-9]{64})"/g,
    ),
  ].map((match) => [`${match[1]}@${match[2]}`, match[3]]),
);
const notices = [
  "# LockedIn Flow desktop dependency notices",
  "",
  "This build inventory includes target and build dependencies, not a claim that every crate is linked at runtime. System libraries and the operating-system webview are administered separately. See desktop/SECURITY.md.",
  "",
];
async function licenseFiles(directory, relative = "") {
  const found = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if ([".git", "target", "node_modules"].includes(item.name)) continue;
    const name = relative + item.name;
    if (item.isDirectory())
      found.push(
        ...(await licenseFiles(path.join(directory, item.name), name + "/")),
      );
    else if (
      item.isFile() &&
      /^(?:licen[cs]e|copying|copyright|notice)(?:[._-].*)?$/i.test(item.name)
    )
      found.push(name);
  }
  return found.sort();
}
const components = [];
for (const pkg of packages) {
  if (!pkg.license)
    throw new Error("A dependency is missing its license expression.");
  const component = {
    type: "library",
    "bom-ref": reference(pkg),
    name: pkg.name,
    version: pkg.version,
    purl: reference(pkg),
    licenses: [{ expression: pkg.license }],
  };
  const checksum = checksums.get(`${pkg.name}@${pkg.version}`);
  if (checksum) component.hashes = [{ alg: "SHA-256", content: checksum }];
  if (pkg.name === "glib") {
    if (path.dirname(pkg.manifest_path) !== path.join(root, "vendor", "glib"))
      throw new Error("The reviewed GLib backport is not selected.");
    component.properties = [
      {
        name: "lockedin:source-modification",
        value:
          "Upstream two-line RUSTSEC-2024-0429 backport; verified by scripts/verify-glib-backport.mjs",
      },
    ];
  }
  components.push(component);
  notices.push(
    `## ${pkg.name} ${pkg.version}`,
    "",
    `License: ${pkg.license}`,
    "",
  );
  const directory = path.dirname(pkg.manifest_path);
  const files = await licenseFiles(directory);
  if (pkg.license_file) {
    const relative = path.relative(
      directory,
      path.resolve(directory, pkg.license_file),
    );
    if (!files.includes(relative)) files.push(relative);
  }
  for (const file of files) {
    const resolved = path.resolve(directory, file);
    if (!resolved.startsWith(directory + path.sep))
      throw new Error("Dependency license escapes its package.");
    const bytes = await readFile(resolved);
    if (bytes.length > 2 * 1024 * 1024 || bytes.includes(0))
      throw new Error("Invalid dependency license text.");
    notices.push(
      `### ${file.replaceAll("\\", "/")}`,
      "",
      bytes.toString("utf8"),
      "",
    );
  }
  if (!files.length && pkg.source)
    notices.push(
      `Published source: https://crates.io/crates/${pkg.name}/${pkg.version}`,
      "",
    );
}
const model = JSON.parse(
  await readFile(path.join(root, "models.json"), "utf8"),
);
components.push({
  type: "machine-learning-model",
  "bom-ref": model.id,
  name: model.name,
  version: model.sha256,
  licenses: [{ license: { id: model.license } }],
  hashes: [{ alg: "SHA-256", content: model.sha256 }],
  externalReferences: [{ type: "distribution", url: model.url }],
});
for (const [label, file] of [
  ["LockedIn Flow", "LICENSE"],
  ["Whisper model", "ThirdPartyLicenses/Whisper-MIT.txt"],
  ["Whisper.cpp", "ThirdPartyLicenses/Whisper-cpp-MIT.txt"],
]) {
  notices.push(
    `## ${label}`,
    "",
    await readFile(path.join(root, "..", file), "utf8"),
    "",
  );
}
const revision = run("git", ["rev-parse", "HEAD"]).trim();
const sourceState = run("git", [
  "status",
  "--porcelain",
  "--untracked-files=all",
]).trim()
  ? "modified"
  : "clean";
const sbom = {
  bomFormat: "CycloneDX",
  specVersion: "1.6",
  version: 1,
  metadata: {
    component: {
      type: "application",
      "bom-ref": "lockedin-flow",
      name: "LockedIn Flow",
      version: "0.5.0-alpha.1",
    },
    properties: [
      { name: "lockedin:source-revision", value: revision },
      { name: "lockedin:source-state", value: sourceState },
      { name: "lockedin:target", value: target },
      { name: "lockedin:cargo-lock-sha256", value: hash(lock) },
      {
        name: "lockedin:npm-lock-sha256",
        value: hash(await readFile(path.join(root, "package-lock.json"))),
      },
      { name: "lockedin:rustc", value: run("rustc", ["--version"]).trim() },
    ],
  },
  components,
  dependencies: [
    {
      ref: "lockedin-flow",
      dependsOn: packages
        .filter((pkg) => pkg.name.startsWith("lockedin-flow-"))
        .map(reference),
    },
    ...packages.map((pkg) => ({
      ref: reference(pkg),
      dependsOn: nodes
        .get(pkg.id)
        .dependencies.map((id) => references.get(id))
        .filter(Boolean)
        .sort(),
    })),
  ],
};
const output = path.join(root, "app/resources/compliance");
await mkdir(output, { recursive: true });
await writeFile(
  path.join(output, "SBOM.cdx.json"),
  JSON.stringify(sbom, null, 2) + "\n",
);
await writeFile(
  path.join(output, "THIRD-PARTY-NOTICES.txt"),
  notices.join("\n"),
);
await writeFile(
  path.join(output, "LICENSE.txt"),
  await readFile(path.join(root, "../LICENSE")),
);
await writeFile(
  path.join(output, "MODEL.json"),
  JSON.stringify(model, null, 2) + "\n",
);
process.stdout.write(
  `Generated ${target} build inventory: ${components.length} components; source ${sourceState}.\n`,
);
