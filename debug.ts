#!/usr/bin/env bun

import { existsSync } from "node:fs";
import { join } from "node:path";

const SCRIPT_DIR = import.meta.dir;
const APP_PATH = join(SCRIPT_DIR, "build/DerivedData/Build/Products/Debug/QCopy Dev.app");
const EXECUTABLE_PATH = join(APP_PATH, "Contents/MacOS/QCopy Dev");

async function run(cmd: string[]): Promise<void> {
  const proc = Bun.spawn(cmd, { cwd: SCRIPT_DIR, stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) throw new Error(`命令失败 (exit ${code}): ${cmd.join(" ")}`);
}

async function main() {
  process.env.DEVELOPER_DIR ??= "/Applications/Xcode.app/Contents/Developer";
  const recordMode = process.argv.includes("--record") || process.argv.includes("-r");

  console.log("▸ 生成 Xcode 工程…");
  await run(["xcodegen", "generate"]);
  console.log("▸ 编译 Debug 版本…");
  await run([
    "xcodebuild",
    "-project", "QCopy.xcodeproj",
    "-scheme", "QCopy",
    "-configuration", "Debug",
    "-derivedDataPath", "build/DerivedData",
    "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=-",
    "build",
  ]);

  if (!existsSync(EXECUTABLE_PATH)) throw new Error(`未找到 Debug 可执行文件: ${EXECUTABLE_PATH}`);

  if (recordMode) {
    console.log("▸ 启动 xctrace Time Profiler…");
    await run(["xcrun", "xctrace", "record", "--template", "Time Profiler", "--launch", "--", EXECUTABLE_PATH]);
  } else {
    console.log("▸ 打开 Instruments…");
    await run(["open", "-a", "Instruments", APP_PATH]);
  }
}

main().catch((error) => {
  console.error(`\n✗ ${error instanceof Error ? error.message : error}`);
  process.exit(1);
});
