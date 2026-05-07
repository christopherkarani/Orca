#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const childProcess = require("child_process");

const packageRoot = path.resolve(__dirname, "..");
const packageJson = require(path.join(packageRoot, "package.json"));
const binDir = path.join(packageRoot, "vendor");
const exeName = process.platform === "win32" ? "aegis.exe" : "aegis";
const installedBinary = path.join(binDir, exeName);

function platformName() {
  if (process.platform === "darwin") return "darwin";
  if (process.platform === "linux") return "linux";
  if (process.platform === "win32") return "windows";
  throw new Error(`unsupported operating system: ${process.platform}`);
}

function archName() {
  if (process.arch === "x64") return "amd64";
  if (process.arch === "arm64") return "arm64";
  throw new Error(`unsupported architecture: ${process.arch}`);
}

function sha256(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

function install() {
  const platform = platformName();
  const arch = archName();
  const key = `${platform}-${arch}`;
  const expected = packageJson.aegis.checksums[key];
  if (!expected || expected.startsWith("PLACEHOLDER_")) {
    console.log("Aegis npm wrapper installed without downloading a binary because checksum placeholders have not been replaced.");
    console.log("Use scripts/install.sh or scripts/install.ps1 with checksums.txt for manual verification.");
    return;
  }

  throw new Error("Binary download is intentionally disabled in the template until release automation injects verified URLs and checksums.");
}

if (process.argv.includes("--install")) {
  install();
  process.exit(0);
}

if (!fs.existsSync(installedBinary)) {
  console.error("Aegis binary is not installed. Reinstall after release automation replaces checksum placeholders.");
  process.exit(1);
}

const result = childProcess.spawnSync(installedBinary, process.argv.slice(2), { stdio: "inherit" });
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status === null ? 1 : result.status);
