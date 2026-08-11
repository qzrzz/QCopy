import { FeatureSection } from "./components/FeatureSection";
import { getSectionsContent } from "./content";
import { Footer } from "./Feature/Footer";
import { StickyHeader } from "./Feature/Header";
import { Hero } from "./Feature/Hero";
import { getCurrentLang, type SupportedLang } from "./i18n/dict";
import ImageHeroShot from "./shots/s2.png";

interface AppProps {
  lang?: SupportedLang;
}

/** QCopy 产品官网首页：Header → Hero → 内容分区 → Footer。 */
export function App({ lang }: AppProps) {
  const currentLang = lang || getCurrentLang();
  const sections = getSectionsContent(currentLang);

  return (
    <main className="homePage" id="top">
      <StickyHeader lang={currentLang} />
      <Hero lang={currentLang} />

      <img src={ImageHeroShot} srcSet={`${ImageHeroShot} 2x`} alt="" className="hero-shot" />

      {sections.map((section) => (
        <FeatureSection key={section.id} section={section} />
      ))}

      <Footer lang={currentLang} />
    </main>
  );
}
