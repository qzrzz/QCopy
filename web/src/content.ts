import type { SupportedLang } from "./i18n/dict";

/**
 * 卡片布局：
 * - left   文案在左 / 上，媒体在右 / 下（默认）
 * - right  文案在右，媒体在左
 * - bottom 文案偏下，媒体偏上
 */
export type CardStyle = "left" | "right" | "bottom";

/** 功能卡片配置。图片 / 视频后续放到 src/shots 或各 Feature 的 assets 目录后在此引用。 */
export interface FeatureCardConfig {
  /** 卡片唯一 ID（同时用于 class featureCard--id） */
  id: string;
  /** 功能标题 */
  title: string;
  /** 功能描述（支持用 \\n 表示换行） */
  desc: string;
  /** 截图 / 合成图 URL（import 或 public 路径） */
  image?: string;
  /** 循环演示视频 */
  video?: string;
  /** 布局样式 */
  style?: CardStyle;
  /** 媒体 alt */
  alt?: string;
  /** 自定义卡片 class */
  cardClassName?: string;
  /** 设计稿节点 ID（可选） */
  dataNodeId?: string;
}

/** 首页分区配置 */
export interface SectionConfig {
  /** 分区 ID（锚点：#section-{id}） */
  id: string;
  /** 分区标题 */
  title: string;
  /** 分区说明 */
  description: string;
  /** 分区内卡片 */
  cards: FeatureCardConfig[];
  /** 分区自定义 class */
  className?: string;
}

/**
 * 多语言全站内容。
 * 修改文案 / 增删分区与卡片，只改这里即可；页面会自动渲染。
 *
 * 媒体补充示例：
 *   import transferShot from "./shots/transfer.png";
 *   { id: "liquid-glass", image: transferShot, ... }
 */
export const sectionsContentMap: Record<SupportedLang, SectionConfig[]> = {
  en: [
    {
      id: "why",
      title: "Why QCopy",
      description:
        "Finder can spend more time preparing than copying — especially with many small files, external disks, or NAS.",
      cards: [
        {
          id: "skip-prep",
          title: "Skip the heavy prep phase",
          desc: "Start transferring sooner.\nLess tree walking, less waiting before real I/O begins.",
          style: "left",
          alt: "QCopy starts transfer without long preparation",
        },
        {
          id: "bulk-friendly",
          title: "Built for bulk work",
          desc: "Large trees, tiny files, external volumes, and network shares.\nStay productive when Finder feels stuck.",
          style: "right",
          alt: "Bulk file transfer with QCopy",
        },
      ],
    },
    {
      id: "features",
      title: "Core features",
      description: "A calm native workspace for copy and move — progress, conflicts, and history in one place.",
      cards: [
        {
          id: "liquid-glass",
          title: "Liquid Glass UI",
          desc: "Native macOS feel with continuous glass surfaces.\nSidebar, path cards, and controls stay visually connected.",
          style: "left",
          alt: "QCopy liquid glass interface",
        },
        {
          id: "copy-move",
          title: "Copy & Move",
          desc: "Transfer files and folders with a clear source → destination flow.\nSwitch modes without leaving the workspace.",
          style: "left",
          alt: "Copy and move modes in QCopy",
        },
        {
          id: "conflicts",
          title: "Conflict handling",
          desc: "Replace, skip, or auto-rename when paths collide.\nYou decide how each conflict is resolved.",
          style: "right",
          alt: "Conflict resolution options",
        },
        {
          id: "progress-history",
          title: "Progress & history",
          desc: "Live progress while work runs.\nReview past operations and get macOS completion notifications.",
          style: "bottom",
          alt: "Transfer progress and history",
        },
      ],
    },
    {
      id: "safety",
      title: "Safety first",
      description: "Guards that prevent easy-to-make destructive mistakes during move and replace.",
      cards: [
        {
          id: "path-guards",
          title: "Path guards",
          desc: "Block dangerous move sources like root, system paths, home, and volume roots.\nRefuse moving a folder into its own parent.",
          style: "left",
          alt: "Path safety guards",
        },
        {
          id: "atomic-replace",
          title: "Safer replace",
          desc: "Write then swap: new content lands in a temp file first.\nOn failure or cancel, the original file stays intact.",
          style: "right",
          alt: "Atomic replace flow",
        },
      ],
    },
  ],

  "zh-Hans": [
    {
      id: "why",
      title: "为什么选择 QCopy",
      description:
        "Finder 在大量文件场景下，往往把时间花在「准备」而不是真正传输——尤其是海量小文件、外置盘与 NAS。",
      cards: [
        {
          id: "skip-prep",
          title: "跳过沉重的准备阶段",
          desc: "更快进入真正的数据传输。\n减少目录树枚举与前置等待。",
          style: "left",
          alt: "QCopy 无需漫长准备即可开始传输",
        },
        {
          id: "bulk-friendly",
          title: "为批量传输而生",
          desc: "大目录树、大量小文件、外置卷与网络共享。\nFinder 卡住时，你还能继续干活。",
          style: "right",
          alt: "QCopy 批量文件传输",
        },
      ],
    },
    {
      id: "features",
      title: "核心能力",
      description: "原生、安静的复制 / 移动工作区——进度、冲突与历史都在一处。",
      cards: [
        {
          id: "liquid-glass",
          title: "Liquid Glass 界面",
          desc: "原生 macOS 观感，连续的玻璃质感。\n侧栏、路径卡片与控件视觉一体。",
          style: "left",
          alt: "QCopy Liquid Glass 界面",
        },
        {
          id: "copy-move",
          title: "复制与移动",
          desc: "清晰的 源 → 目标 传输流程。\n无需离开工作区即可切换模式。",
          style: "left",
          alt: "QCopy 复制与移动模式",
        },
        {
          id: "conflicts",
          title: "冲突处理",
          desc: "路径冲突时可替换、跳过或自动重命名。\n每次冲突如何处理，由你决定。",
          style: "right",
          alt: "冲突处理选项",
        },
        {
          id: "progress-history",
          title: "进度与历史",
          desc: "传输过程实时进度。\n回顾历史操作，并接收 macOS 完成通知。",
          style: "bottom",
          alt: "传输进度与历史记录",
        },
      ],
    },
    {
      id: "safety",
      title: "安全优先",
      description: "针对移动与替换中容易踩坑的路径与写入策略做防呆。",
      cards: [
        {
          id: "path-guards",
          title: "路径防护",
          desc: "拦截根目录、系统敏感路径、用户主目录与磁盘根等危险移动来源。\n禁止把文件夹移动到它自己的父目录。",
          style: "left",
          alt: "路径安全防护",
        },
        {
          id: "atomic-replace",
          title: "更安全的替换",
          desc: "先写后换：新内容先写入同目录临时文件。\n失败或取消时，原文件保持不变。",
          style: "right",
          alt: "安全替换流程",
        },
      ],
    },
  ],
};

/** 根据语言获取分区列表。 */
export function getSectionsContent(lang: SupportedLang): SectionConfig[] {
  return sectionsContentMap[lang] || sectionsContentMap.en;
}

/** 导航用的分区摘要（Header 锚点等）。 */
export function getSectionNav(
  lang: SupportedLang,
): Array<{ id: string; title: string; href: string }> {
  return getSectionsContent(lang).map((section) => ({
    id: section.id,
    title: section.title,
    href: `#section-${section.id}`,
  }));
}
