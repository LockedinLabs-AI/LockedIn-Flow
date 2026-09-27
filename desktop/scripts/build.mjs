#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import os from "node:os";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cli = path.join(root, "node_modules", "@tauri-apps", "cli", "tauri.js");
const env = { ...process.env };
const buildArgs = process.argv.slice(2);
const targetIndex = buildArgs.indexOf("--target");
const target = targetIndex >= 0 ? buildArgs[targetIndex + 1] : undefined;
if (targetIndex >= 0 && !target) throw new Error("A build target is required.");
const mappings = [
  [path.dirname(root), "/lockedin-flow"],
  [env.CARGO_HOME ?? path.join(os.homedir(), ".cargo"), "/cargo"],
  [env.RUSTUP_HOME ?? path.join(os.homedir(), ".rustup"), "/rustup"],
];
const rustFlags =
  env.CARGO_ENCODED_RUSTFLAGS?.split("\u001f") ??
  env.RUSTFLAGS?.split(/\s+/).filter(Boolean) ??
  [];
env.CARGO_ENCODED_RUSTFLAGS = [
  ...rustFlags,
  ...mappings.map(([from, to]) => `--remap-path-prefix=${from}=${to}`),
].join("\u001f");
const nativeFlags = mappings
  .map(([from, to]) =>
    process.platform === "win32"
      ? `/pathmap:"${from}"=${to}`
      : `-ffile-prefix-map="${from}"=${to}`,
  )
  .join(" ");
env.CXXFLAGS = [env.CXXFLAGS, nativeFlags].filter(Boolean).join(" ");
env.CFLAGS = [env.CFLAGS, nativeFlags].filter(Boolean).join(" ");
for (const script of ["provision-model.mjs", "generate-inventory.mjs"]) {
  const arguments_ =
    script === "provision-model.mjs" ? ["--verify"] : target ? [target] : [];
  const prerequisite = spawnSync(
    process.execPath,
    [path.join(root, "scripts", script), ...arguments_],
    { cwd: root, env, stdio: "inherit", shell: false },
  );
  if (prerequisite.status !== 0) process.exit(prerequisite.status ?? 1);
}
if (process.platform === "darwin") {
  env.MACOSX_DEPLOYMENT_TARGET = "13.0";
  env.CMAKE_OSX_DEPLOYMENT_TARGET = "13.0";
}
const result = spawnSync(
  process.execPath,
  [
    cli,
    "build",
    "--config",
    "app/tauri.conf.json",
    ...buildArgs,
    "--",
    "--locked",
  ],
  { cwd: root, env, stdio: "inherit", shell: false },
);
process.exit(result.status ?? 1);
