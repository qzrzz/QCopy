#!/usr/bin/env bun

import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";

const ROOT_DIR = join(import.meta.dir, "..");
const BUILD_DIR = join(ROOT_DIR, "build");
const PROJECT_FILE = join(ROOT_DIR, "QCopy.xcodeproj");

async function run(cmd: string[]): Promise<void> {
  const proc = Bun.spawn(cmd, { cwd: ROOT_DIR, stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) throw new Error(`命令失败 (exit ${code}): ${cmd.join(" ")}`);
}

async function main() {
  console.log("🧹 清理 QCopy 构建产物…");
  if (existsSync(PROJECT_FILE)) {
    try {
      await run(["xcodebuild", "-project", "QCopy.xcodeproj", "-scheme", "QCopy", "clean"]);
    } catch {
      console.warn("⚠️ xcodebuild clean 未完成，继续删除 build 目录");
    }
  }
  if (existsSync(BUILD_DIR)) rmSync(BUILD_DIR, { recursive: true, force: true });
  console.log("✓ 清理完成");
}

main().catch((error) => {
  console.error(`❌ 清理失败: ${error instanceof Error ? error.message : error}`);
  process.exit(1);
});
