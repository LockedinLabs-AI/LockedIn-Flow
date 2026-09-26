#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { localLinks, scanEntry, scanText } from "./lib/public-content-policy.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
if (args.some((arg) => arg !== "--history") || args.length > 1) {
  console.error("Usage: node scripts/check-public-content.mjs [--history]");
  process.exit(64);
}
const history = args.includes("--history");
const failures = new Set();
let fileCount = 0;
let revisionCount = 0;
const git = (...parameters) => execFileSync("git", parameters, {
  cwd: root, maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"],
});
const report = (file, rules, revision = "working tree") => {
  const identifier = createHash("sha256").update(file).digest("hex").slice(0, 12);
  for (const rule of rules) failures.add(`${revision}: entry-${identifier} [${rule}]`);
};

function checkLinks(entries, revision) {
  const files = new Set(entries.map(({ file }) => file));
  for (const { file, bytes } of entries) {
    for (const target of localLinks(file, bytes.toString("utf8"))) {
      const present = files.has(target) || [...files].some((candidate) => candidate.startsWith(`${target}/`));
      if (target.startsWith("../") || target.startsWith("/") || !present) {
        report(file, ["broken-or-external-local-link"], revision);
      }
    }
  }
}

try {
  if (history) {
    if (git("rev-parse", "--is-shallow-repository").toString().trim() !== "false") {
      throw new Error("A complete clone is required for history review.");
    }
    const revisions = git("rev-list", "--all").toString().trim().split("\n").filter(Boolean);
    if (!revisions.length) throw new Error("No committed history to review.");
    const checked = new Set();
    for (const revision of revisions) {
      const entries = git("ls-tree", "-rz", revision).toString().split("\0").filter(Boolean).map((row) => {
        const [header, file] = row.split(/\t(.+)/s);
        const [mode, , oid] = header.split(" ");
        return { mode, oid, file };
      });
      const manifest = entries.find(({ file }) => file === "security/public-media.json");
      const media = manifest ? JSON.parse(git("cat-file", "blob", manifest.oid).toString()).assets : {};
      const contents = [];
      for (const entry of entries) {
        const key = `${entry.file}:${entry.oid}:${media[entry.file] ?? ""}`;
        const bytes = ["100644", "100755"].includes(entry.mode) ? git("cat-file", "blob", entry.oid) : Buffer.alloc(0);
        contents.push({ file: entry.file, bytes });
        if (checked.has(key)) continue;
        checked.add(key);
        report(entry.file, scanEntry(entry.file, bytes, { mode: entry.mode, media }), revision.slice(0, 12));
        fileCount++;
      }
      const metadata = git("show", "-s", "--format=%an%n%ae%n%cn%n%ce%n%B", revision).toString();
      report("commit metadata", scanText(metadata, { commitMetadata: true }), revision.slice(0, 12));
      checkLinks(contents, revision.slice(0, 12));
      revisionCount++;
    }
  } else {
    const media = JSON.parse(readFileSync(path.join(root, "security/public-media.json"), "utf8")).assets;
    const files = [...new Set(git("ls-files", "-z", "--cached", "--others", "--exclude-standard").toString().split("\0").filter(Boolean))];
    const entries = [];
    for (const file of files) {
      const full = path.join(root, file);
      let stat;
      try { stat = lstatSync(full); } catch { continue; } // Tracked deletions are not published.
      if (!stat.isFile() || stat.isSymbolicLink()) { report(file, ["nonregular-git-entry"]); continue; }
      const bytes = readFileSync(full);
      entries.push({ file, bytes });
      report(file, scanEntry(file, bytes, { media }));
      fileCount++;
    }
    checkLinks(entries, "working tree");
  }
} catch (error) {
  // Never echo git errors or raw file contents into a public CI log.
  console.error("Publication check could not complete. Verify the repository, full history, and media manifest locally.");
  process.exit(1);
}

if (failures.size) {
  console.error(`Publication check failed (${failures.size} findings). Content and unreviewed paths are withheld; entry IDs are SHA-256 path prefixes.`);
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`Publication check passed: ${fileCount} file versions${history ? ` across ${revisionCount} reachable commits` : " in the candidate tree"}. Media and prose still require human review.`);
