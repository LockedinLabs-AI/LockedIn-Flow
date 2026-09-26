#!/usr/bin/env node
// Remove ancillary metadata only. Compressed pixel data remains byte-identical.
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { stripPngMetadata } from "./lib/public-content-policy.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const { assets } = JSON.parse(readFileSync(path.join(root, "security/public-media.json"), "utf8"));
const outputs = Object.keys(assets).map((file) => {
  if (!/^(?:branding\/raster|docs\/images)\/[a-z0-9-]+\.png$/.test(file)) {
    throw new Error("Unapproved media path in the review inventory.");
  }
  const location = path.join(root, file);
  return { location, bytes: stripPngMetadata(readFileSync(location)) };
});
for (const { location, bytes } of outputs) writeFileSync(location, bytes);
console.log(`Removed ancillary metadata from ${outputs.length} approved images without changing pixel data. Review the images before updating their hash inventory.`);
