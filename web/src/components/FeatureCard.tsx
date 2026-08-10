import type { ReactNode } from "react";
import type { FeatureCardConfig } from "../content";

interface FeatureCardProps {
  card: FeatureCardConfig;
}

/** 将含 `\n` 的描述渲染为多行。 */
function renderMultilineText(text: string): ReactNode {
  const lines = text.split("\n");
  return lines.map((line, index) => (
    <span key={index}>
      {line}
      {index < lines.length - 1 ? <br /> : null}
    </span>
  ));
}

/**
 * 通用功能卡片。
 * 布局修饰：featureCard--left | --right | --bottom；
 * ID 修饰：featureCard--{id}，便于后续按卡片微调样式。
 */
export function FeatureCard({ card }: FeatureCardProps) {
  const {
    id,
    title,
    desc,
    image,
    video,
    style = "left",
    alt,
    cardClassName,
    dataNodeId,
  } = card;

  const containerClasses = [
    "featureCard",
    `featureCard--${style}`,
    `featureCard--${id}`,
    !image && !video ? "featureCard--placeholder" : null,
    cardClassName,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <article className={containerClasses} data-node-id={dataNodeId}>
      <div className="featureCard__info">
        <h3>{title}</h3>
        <p>{renderMultilineText(desc)}</p>
      </div>

      {video ? (
        <div className="featureCard__media">
          <video
            className="featureCard__video"
            src={video}
            autoPlay
            loop
            muted
            playsInline
            aria-label={alt || title}
          />
        </div>
      ) : image ? (
        <div className="featureCard__media">
          <img className="featureCard__shot" src={image} alt={alt || title} />
        </div>
      ) : (
        <div className="featureCard__media featureCard__media--empty" aria-hidden="true">
          <span className="featureCard__placeholderLabel">{id}</span>
        </div>
      )}
    </article>
  );
}
