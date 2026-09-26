#!/usr/bin/env node
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { provisionModels } from "./lib/model-provisioning.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let destinationRoot = path.join(
  homedir(),
  "Library",
  "Application Support",
  "LockedInFlowCommunity",
  "FluidAudio",
  "Models",
);
let includeOptional = false;
let repairInvalid = false;
let permissionProfile = "user";
let destinationWasExplicit = false;

const args = process.argv.slice(2);
for (let index = 0; index < args.length; index += 1) {
  switch (args[index]) {
    case "--all":
      includeOptional = true;
      break;
    case "--repair":
      repairInvalid = true;
      break;
    case "--managed":
      permissionProfile = "managed";
      break;
    case "--destination":
      if (!args[index + 1]) throw new Error("--destination needs an absolute path.");
      destinationRoot = args[index + 1];
      destinationWasExplicit = true;
      index += 1;
      break;
    case "--help":
    case "-h":
      console.log(`Usage: scripts/provision-models.mjs [--all] [--repair] [--managed] [--destination <absolute-path>]

Downloads the default speech-recognition and voice-activity models from pinned
Hugging Face revisions, verifies every byte against the reviewed SHA-256
manifest, and atomically installs each complete model directory. --all also
provisions the optional English Precision model. --repair stages and verifies a
replacement before atomically replacing an existing invalid model. --managed
requires an explicit destination and emits package-ready 0755 directories and
0644 files; the default per-user profile remains private at 0700 and 0600. Every
destination must be a dedicated absolute path ending in Models; filesystem,
system, home-root, linked-parent, and all /tmp, /private/tmp, and /var/tmp
descendants are rejected. One provisioner may modify a destination at a time.`);
      process.exit(0);
      break;
    default:
      throw new Error(`Unknown option: ${args[index]}`);
  }
}

if (permissionProfile === "managed" && !destinationWasExplicit) {
  console.error("--managed requires an explicit absolute --destination.");
  process.exit(64);
}

console.log("This explicit provisioning step contacts only the pinned model hosts.");
console.log(`Destination: ${destinationRoot}`);
console.log(`Permissions: ${permissionProfile}`);
try {
  const installed = await provisionModels({
    repositoryRoot,
    destinationRoot,
    includeOptional,
    repairInvalid,
    permissionProfile,
  });
  console.log(`Provisioning complete: ${installed.join(", ")}`);
} catch (error) {
  console.error(`Provisioning failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
