import { getSectionNav } from "../../content";
import { uiDictMap, type SupportedLang } from "../../i18n/dict";
import "./StickyHeader.css";

interface StickyHeaderProps {
  lang?: SupportedLang;
}

/** 顶部导航：品牌 + 分区锚点 + GitHub。 */
export function StickyHeader({ lang = "en" }: StickyHeaderProps) {
  const dict = uiDictMap[lang] || uiDictMap.en;
  const nav = getSectionNav(lang);

  return (
    <header className="stickyHeader">
      <a className="stickyHeaderBrand" href="#top">
        <img src="./qcopy-icon.png" width="28" height="28" alt="" />
        <span>{dict.brand}</span>
      </a>

      <nav className="stickyHeaderNav" aria-label="Primary">
        {nav.map((item) => (
          <a key={item.id} className="stickyHeaderLink" href={item.href}>
            {item.title}
          </a>
        ))}
        <a
          className="stickyHeaderLink stickyHeaderLink--external"
          href="https://github.com/qzrzz/QCopy"
          target="_blank"
          rel="noreferrer"
        >
          {dict.viewOnGithub}
        </a>
      </nav>
    </header>
  );
}
