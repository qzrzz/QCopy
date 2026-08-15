import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const CURRENT_DIR = import.meta.dirname ?? import.meta.dir ?? process.cwd();
const PACKAGE_JSON_PATH = join(CURRENT_DIR, "package.json");

/**
 * package.json 元数据类型定义
 */
export interface PackageMetadata {
  version?: string;
  [key: string]: unknown;
}

/**
 * 读取并解析根目录下的 package.json
 * @returns 包含路径和解析后的 JSON 对象的结构
 */
export function readPackageMetadata(): {
  path: string;
  packageJson: PackageMetadata;
} {
  if (!existsSync(PACKAGE_JSON_PATH)) {
    throw new Error(`未找到 package.json: ${PACKAGE_JSON_PATH}`);
  }

  try {
    return {
      path: PACKAGE_JSON_PATH,
      packageJson: JSON.parse(readFileSync(PACKAGE_JSON_PATH, "utf8")) as PackageMetadata,
    };
  } catch (error) {
    throw new Error(`解析 package.json 失败: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * 获取 package.json 中的当前版本号
 * @returns 版本号字符串（如 '1.0.3'）
 */
export function readPackageVersion(): string {
  const { packageJson } = readPackageMetadata();
  if (!packageJson.version || typeof packageJson.version !== "string") {
    throw new Error("package.json 中未找到有效的 version 字段");
  }
  return packageJson.version;
}

/**
 * 从 project.yml 中读取当前工程构建号 CURRENT_PROJECT_VERSION
 * @param projectYmlPath project.yml 文件路径（默认在当前目录）
 * @returns 构建号字符串（如 '7'）
 */
export function readProjectBuildNumber(projectYmlPath = join(CURRENT_DIR, "project.yml")): string {
  const content = readFileSync(projectYmlPath, "utf8");
  const match = content.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/);
  if (!match) throw new Error(`project.yml 中未找到 CURRENT_PROJECT_VERSION: ${projectYmlPath}`);
  return match[1];
}

/**
 * 校验版本号是否符合语义化版本规范 (X.Y.Z)
 * @param value 待校验版本字符串
 * @returns 是否符合 SemVer 格式
 */
export function isSemVer(value: string): boolean {
  return /^\d+\.\d+\.\d+$/.test(value);
}
