#!/usr/bin/env bun

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { isSemVer, readPackageMetadata } from "../version";

const ROOT_DIR = join(import.meta.dir, "..");
const PROJECT_YML_PATH = join(ROOT_DIR, "project.yml");

function parseSemVer(version: string): [number, number, number] {
  if (!isSemVer(version)) throw new Error(`无法解析版本号 "${version}"，期望 X.Y.Z`);
  return version.split(".").map(Number) as [number, number, number];
}

async function run(cmd: string[]): Promise<void> {
  const proc = Bun.spawn(cmd, { cwd: ROOT_DIR, stdout: "ignore", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) throw new Error(`命令失败 (exit ${code}): ${cmd.join(" ")}`);
}

async function main() {
  if (!existsSync(PROJECT_YML_PATH)) throw new Error(`未找到配置文件: ${PROJECT_YML_PATH}`);

  const projectYml = readFileSync(PROJECT_YML_PATH, "utf8");
  const marketingMatch = projectYml.match(/MARKETING_VERSION:\s*"([^"]+)"/);
  const buildMatch = projectYml.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/);
  if (!marketingMatch || !buildMatch) {
    throw new Error("project.yml 中未找到 MARKETING_VERSION 或 CURRENT_PROJECT_VERSION");
  }

  const currentVersion = marketingMatch[1];
  const currentBuild = Number.parseInt(buildMatch[1], 10);
  const arg = process.argv[2]?.trim().toLowerCase() || "patch";
  const [major, minor, patch] = parseSemVer(currentVersion);

  let nextVersion: string;
  switch (arg) {
    case "patch": nextVersion = `${major}.${minor}.${patch + 1}`; break;
    case "minor": nextVersion = `${major}.${minor + 1}.0`; break;
    case "major": nextVersion = `${major + 1}.0.0`; break;
    default:
      if (!isSemVer(arg)) throw new Error(`无效参数 "${arg}"；使用 patch、minor、major 或 1.2.3`);
      nextVersion = arg;
  }

  const nextBuild = String(Number.isNaN(currentBuild) ? 1 : currentBuild + 1);
  let nextYml = projectYml.replace(/MARKETING_VERSION:\s*"([^"]+)"/, `MARKETING_VERSION: "${nextVersion}"`);
  nextYml = nextYml.replace(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/, `CURRENT_PROJECT_VERSION: "${nextBuild}"`);
  writeFileSync(PROJECT_YML_PATH, nextYml, "utf8");

  const { path: packagePath, packageJson } = readPackageMetadata();
  packageJson.version = nextVersion;
  writeFileSync(packagePath, JSON.stringify(packageJson, null, 2) + "\n", "utf8");

  let generated = false;
  try {
    await run(["xcodegen", "generate"]);
    generated = true;
  } catch {
    console.warn("⚠️ xcodegen generate 未执行成功，版本文件仍已更新");
  }

  console.log("✨ 版本号更新完成");
  console.log(`  version: ${currentVersion} → ${nextVersion}`);
  console.log(`  build:   ${buildMatch[1]} → ${nextBuild}`);
  console.log(`  files:   package.json, project.yml${generated ? ", QCopy.xcodeproj" : ""}`);
}

main().catch((error) => {
  console.error(`❌ 版本更新失败: ${error instanceof Error ? error.message : error}`);
  process.exit(1);
});
