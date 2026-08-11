import { LanguageSwitcher } from "../../components/LanguageSwitcher";
import { getSectionsContent } from "../../content";
import { getRootRelativePath, uiDictMap, type SupportedLang } from "../../i18n/dict";
import "./StickyHeader.css";

interface StickyHeaderProps {
  lang?: SupportedLang;
}

/** 顶部导航：品牌 + Why QCopy + Download / GitHub + 语言切换。 */
export function StickyHeader({ lang = "en" }: StickyHeaderProps) {
  const dict = uiDictMap[lang] || uiDictMap.en;
  const iconSrc = getRootRelativePath("qcopy-icon.png", lang);
  const whySection = getSectionsContent(lang).find((s) => s.id === "why");
  const whyTitle = whySection?.title ?? (lang === "zh-Hans" ? "为什么选择 QCopy" : "Why QCopy");

  return (
    <header className="stickyHeader">
      <a className="stickyHeaderBrand" href="#top">
        <img src={iconSrc} width="28" height="28" alt="" />
        <span>{dict.brand}</span>
      </a>

      <div className="stickyHeaderActions">
        <nav className="stickyHeaderNav" aria-label="Primary">
          <a className="stickyHeaderLink" href="#section-why">
            {whyTitle}
          </a>
          <a
            className="stickyHeaderLink stickyHeaderLink--external"
            href="https://github.com/qzrzz/QCopy"
            target="_blank"
            rel="noreferrer"
          >
            {dict.viewOnGithub}
          </a>
          <a
            className="stickyHeaderLink stickyHeaderLink--action"
            href="https://github.com/qzrzz/QCopy/releases/latest"
            target="_blank"
            rel="noreferrer"
          >
            {dict.download}
          </a>
        </nav>
        <LanguageSwitcher currentLang={lang} />
      </div>
    </header>
  );
}
