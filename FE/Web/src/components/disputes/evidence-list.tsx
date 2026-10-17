// src/components/disputes/evidence-list.tsx
// Complaint evidence: source links open in a new tab (noopener noreferrer); images show as
// thumbnails that open the full image. URLs come from app users, so only http(s) is rendered
// as a link — anything else (javascript:, data:…) is shown as plain text and flagged.
import { ExternalLink, ImageIcon, Link2, TriangleAlert } from "lucide-react";

import type { ComplaintEvidence } from "@/types/bookings";

import { formatVnDateTime } from "./booking-badges";

/** Normalised http(s) URL, or null when the value is not a safe web link. */
export function safeHttpUrl(raw: string): string | null {
  try {
    const url = new URL(raw.trim());
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
}

/** "https://www.fda.gov/consumers/…" → "fda.gov" */
const hostOf = (href: string) => new URL(href).hostname.replace(/^www\./, "");

export function EvidenceList({ evidence, emptyText = "Không có bằng chứng." }: { evidence: ComplaintEvidence[]; emptyText?: string }) {
  if (evidence.length === 0) {
    return <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">{emptyText}</p>;
  }
  const images = evidence.filter((e) => e.kind === "Image");
  const links = evidence.filter((e) => e.kind === "Link");
  return (
    <div className="flex flex-col gap-3">
      {images.length > 0 && (
        <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3" aria-label="Ảnh bằng chứng">
          {images.map((e) => {
            const href = safeHttpUrl(e.url);
            const label = e.caption ?? "Ảnh bằng chứng";
            return (
              <li key={e.id} className="min-w-0">
                {href ? (
                  <a
                    href={href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="group flex flex-col gap-1 rounded-lg focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                    aria-label={`Mở ảnh trong tab mới: ${label}`}
                  >
                    <span className="relative flex aspect-[4/3] items-center justify-center overflow-hidden rounded-lg border bg-muted text-muted-foreground">
                      <ImageIcon className="size-6" aria-hidden />
                      {/* Background image: if it fails to load, the icon underneath stays visible. */}
                      <span
                        aria-hidden
                        className="absolute inset-0 bg-cover bg-center transition-transform group-hover:scale-105"
                        style={{ backgroundImage: `url("${href}")` }}
                      />
                    </span>
                    <span className="line-clamp-2 text-xs text-muted-foreground group-hover:text-foreground">{label}</span>
                  </a>
                ) : (
                  <UnsafeUrl url={e.url} caption={label} />
                )}
              </li>
            );
          })}
        </ul>
      )}
      {links.length > 0 && (
        <ul className="flex flex-col gap-2" aria-label="Liên kết nguồn">
          {links.map((e) => {
            const href = safeHttpUrl(e.url);
            return (
              <li key={e.id} className="min-w-0">
                {href ? (
                  <a
                    href={href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-start gap-2.5 rounded-lg border p-3 text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                  >
                    <Link2 className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden />
                    <span className="min-w-0 flex-1">
                      <span className="block font-semibold leading-snug">{e.caption ?? hostOf(href)}</span>
                      <span className="block truncate text-xs text-muted-foreground">{href}</span>
                      <span className="block text-xs text-muted-foreground">
                        {e.submittedBy === "chef" ? "Chuyên gia gửi" : "Thành viên gửi"} · {formatVnDateTime(e.createdAt)}
                      </span>
                    </span>
                    <ExternalLink className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden />
                    <span className="sr-only">(mở trong tab mới)</span>
                  </a>
                ) : (
                  <UnsafeUrl url={e.url} caption={e.caption ?? "Liên kết"} />
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function UnsafeUrl({ url, caption }: { url: string; caption: string }) {
  return (
    <div className="flex items-start gap-2 rounded-lg border border-ochre-border bg-ochre-soft p-3 text-xs text-ochre-text">
      <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
      <span className="min-w-0">
        <span className="block font-semibold">{caption} — liên kết không hợp lệ, không mở được</span>
        <span className="block break-all font-mono">{url}</span>
      </span>
    </div>
  );
}
