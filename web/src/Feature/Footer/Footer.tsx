import {
  getRootRelativePath,
  STUDIO_URL,
  uiDictMap,
  type SupportedLang,
} from "../../i18n/dict";
import "./Footer.css";

interface FooterProps {
  lang?: SupportedLang;
}

/** 页脚。 */
export function Footer({ lang = "en" }: FooterProps) {
  const dict = uiDictMap[lang] || uiDictMap.en;
  const iconSrc = getRootRelativePath("qcopy-icon.png", lang);

  return (
    <footer className="siteFooter">
      <div className="siteFooterInner">
        <a className="siteFooterBrand" href="#top">
          <img src={iconSrc} width="28" height="28" alt="" />
          <span>{dict.brand}</span>
        </a>
        <p className="siteFooterTagline">{dict.footerTagline}</p>
        <div className="siteFooterLinks">
          <a
            href="https://github.com/qzrzz/QCopy"
            target="_blank"
            rel="noreferrer"
          >
            {dict.viewOnGithub}
          </a>
          <a
            href="https://github.com/qzrzz/QCopy/releases/latest"
            target="_blank"
            rel="noreferrer"
          >
            {dict.download}
          </a>
        </div>
        <p className="siteFooterCopyright">
          <span>{dict.copyright}</span>{" "}
          <a
            className="siteFooterStudio"
            href={STUDIO_URL}
            target="_blank"
            rel="noreferrer"
          >
            {dict.studioName}
          </a>
        </p>
      </div>
    </footer>
  );
}
