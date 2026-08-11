import type { SupportedLang } from "./i18n/dict";

import ImageS1 from "./shots/s1.png";
import ImageS3 from "./shots/s3.png";
import ImageReady from "./shots/macosReady.png";

/**
 * 卡片布局：
 * - left   媒体偏左（默认）
 * - right  媒体偏右
 * - bottom 媒体偏下
 * - center 图片水平垂直居中
 */
export type CardStyle = "left" | "right" | "bottom" | "center";

/** 功能卡片：只需图片与布局。 */
export interface FeatureCardConfig {
  /**
   * 截图 / 合成图（import 或 public 路径）。
   * 默认按 **2x** 资源渲染：`srcSet="${image} 2x"`。
   */
  image?: string;
  /** 布局样式 */
  style?: CardStyle;
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
 * 卡片只配 image + style；文案按语言维护。
 */
export const sectionsContentMap: Record<SupportedLang, SectionConfig[]> = {
  en: [
    {
      id: "why",
      title: "Why QCopy",
      description:
        "Copying thousands of small files to a NAS or external drive? No more waiting forever at “Preparing to Move…”\nIf you know FastCopy or Robocopy on Windows, think of QCopy as the macOS alternative.",
      cards: [{ style: "center", image: ImageReady }],
    },
    {
      id: "features",
      title: "Copy & Move",
      description:
        "Simple Copy & Move. Skip the pre-copy preparation and detailed progress tracking for faster transfers of large numbers of small files.",
      cards: [{ style: "center", image: ImageS1 }],
    },
    {
      id: "history",
      title: "Copy History",
      description: "Keep a detailed record of every transfer.",
      cards: [{ style: "center", image: ImageS3 }],
    },
  ],

  "zh-Hans": [
    {
      id: "why",
      title: "为什么选择 QCopy",
      description:
        "要把成千上万小文件拷到 NAS 或外置盘？不必再卡在「正在准备移动…」。\n如果你用过 Windows 上的 FastCopy / Robocopy，可以把 QCopy 当作 macOS 上的同类工具。",
      cards: [{ style: "center", image: ImageReady }],
    },
    {
      id: "features",
      title: "复制与移动",
      description:
        "简单的复制 / 移动。跳过冗长的预拷贝准备，并提供清晰进度，海量小文件传输更快。",
      cards: [{ style: "center", image: ImageS1 }],
    },
    {
      id: "history",
      title: "复制记录",
      description: "完整保留每一次传输的详细记录。",
      cards: [{ style: "center", image: ImageS3 }],
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
