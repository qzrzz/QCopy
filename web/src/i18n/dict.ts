/** 官网支持的语言。 */
export type SupportedLang = "en" | "zh-Hans";

const LANG_STORAGE_KEY = "qcopy_lang";

export type UiDict = {
  siteTitle: string;
  metaDesc: string;
  brand: string;
  tagline: string;
  download: string;
  viewOnGithub: string;
  footerTagline: string;
  copyright: string;
};

export const uiDictMap: Record<SupportedLang, UiDict> = {
  en: {
    siteTitle: "QCopy",
    metaDesc: "A native macOS file copy tool.",
    brand: "QCopy",
    tagline: "Native macOS file copy, done right.",
    download: "Download",
    viewOnGithub: "GitHub",
    footerTagline: "A native macOS file copy tool.",
    copyright: "© QCopy",
  },
  "zh-Hans": {
    siteTitle: "QCopy",
    metaDesc: "原生 macOS 文件复制工具。",
    brand: "QCopy",
    tagline: "原生 macOS 文件复制，更快更稳。",
    download: "下载",
    viewOnGithub: "GitHub",
    footerTagline: "原生 macOS 文件复制工具。",
    copyright: "© QCopy",
  },
};

/** 从路径或 localStorage 解析当前语言，默认英文。 */
export function getCurrentLang(): SupportedLang {
  if (typeof window === "undefined") {
    return "en";
  }

  try {
    const path = window.location.pathname;
    if (path.includes("/zh-Hans")) {
      return "zh-Hans";
    }

    const saved = localStorage.getItem(LANG_STORAGE_KEY);
    if (saved === "zh-Hans" || saved === "en") {
      return saved;
    }
  } catch {
    // ignore
  }

  return "en";
}

/** 持久化语言选择。 */
export function setCurrentLang(lang: SupportedLang): void {
  try {
    localStorage.setItem(LANG_STORAGE_KEY, lang);
  } catch {
    // ignore
  }
}
