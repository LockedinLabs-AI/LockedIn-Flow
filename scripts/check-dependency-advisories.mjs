#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dependencyQueries, queryAdvisories } from "./lib/dependency-advisories.mjs";

const read = (file) => JSON.parse(readFileSync(new URL(`../${file}`, import.meta.url), "utf8"));
try {
  if (process.argv.length !== 2) throw new Error("No arguments supported.");
  const queries = dependencyQueries(read("Package.resolved"),
    read("security/dependency-revisions.json"), read("security/sbom-components.json"));
  const results = await Promise.all(queries.map(async (entry) => ({
    ...entry, advisories: await queryAdvisories(entry.commit),
  })));
  console.log(JSON.stringify({ checkedAt: new Date().toISOString(), provider: "OSV",
    scope: "Pinned Swift and vendored upstream revisions; not model weights, OS frameworks, or unversioned embedded code.", results }, null, 2));
  if (results.some((result) => result.advisories.length)) process.exitCode = 1;
} catch {
  console.error("Dependency advisory check incomplete. Release remains blocked; no remote error content is printed.");
  process.exitCode = 1;
}
