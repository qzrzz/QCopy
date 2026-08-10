import { uiDictMap, type SupportedLang } from "../../i18n/dict";
import "./Hero.css";

interface HeroProps {
  lang?: SupportedLang;
}

/** 首屏骨架：品牌、一句话介绍与下载入口占位。 */
export function Hero({ lang = "en" }: HeroProps) {
  const dict = uiDictMap[lang] || uiDictMap.en;

  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="heroInner">
        <img
          className="heroIcon"
          src="./qcopy-icon.png"
          width="96"
          height="96"
          alt=""
          decoding="async"
        />
        <h1 id="hero-title" className="heroTitle">
          {dict.brand}
        </h1>
        <p className="heroTagline">{dict.tagline}</p>
        <div className="heroActions">
          <a
            className="heroPrimaryBtn"
            href="https://github.com/qzrzz/QCopy/releases/latest"
            target="_blank"
            rel="noreferrer"
          >
            {dict.download}
          </a>
          <a
            className="heroSecondaryBtn"
            href="https://github.com/qzrzz/QCopy"
            target="_blank"
            rel="noreferrer"
          >
            {dict.viewOnGithub}
          </a>
        </div>
      </div>
    </section>
  );
}
