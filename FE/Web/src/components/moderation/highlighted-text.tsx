// src/components/moderation/highlighted-text.tsx
import { FLAG_CATEGORY_LABEL, type FlagSpan } from "@/types/moderation";

/**
 * Renders the post with the spans the model relied on marked
 * (lavender background + underline, so it never relies on colour alone).
 */
export function HighlightedText({ text, spans }: { text: string; spans: FlagSpan[] }) {
  const parts: React.ReactNode[] = [];
  let cursor = 0;

  [...spans]
    .sort((a, b) => a.start - b.start)
    .forEach((span, i) => {
      if (span.start < cursor) return; // overlapping spans: keep the first
      if (span.start > cursor) parts.push(text.slice(cursor, span.start));
      parts.push(
        <mark
          key={`${span.start}-${i}`}
          title={FLAG_CATEGORY_LABEL[span.category]}
          className="rounded-sm bg-ai-soft px-0.5 text-foreground underline decoration-ai decoration-2 underline-offset-4"
        >
          {text.slice(span.start, span.end)}
          <span className="sr-only"> (AI đánh dấu: {FLAG_CATEGORY_LABEL[span.category]})</span>
        </mark>,
      );
      cursor = span.end;
    });

  if (cursor < text.length) parts.push(text.slice(cursor));
  return <p className="text-[15px] leading-7">{parts}</p>;
}
