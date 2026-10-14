// src/components/telemetry/task-filter.tsx
"use client";

import { cn } from "@/lib/utils";
import { TASK_LABEL, type AiTaskType } from "@/types/moderation";

const OPTIONS: (AiTaskType | "all")[] = ["all", "moderation", "meal_plan", "chatbot", "vision_scan"];

export function TaskFilter({ value, onChange }: { value: AiTaskType | "all"; onChange: (v: AiTaskType | "all") => void }) {
  return (
    <div role="radiogroup" aria-label="Lọc theo tác vụ" className="inline-flex flex-wrap gap-1 rounded-lg bg-muted p-1">
      {OPTIONS.map((option) => {
        const active = option === value;
        return (
          <button
            key={option}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => onChange(option)}
            className={cn(
              "h-8 rounded-md px-3 text-sm font-semibold text-muted-foreground transition-colors outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40",
              active ? "bg-card text-foreground shadow-sm" : "hover:text-foreground",
            )}
          >
            {option === "all" ? "Tất cả" : TASK_LABEL[option]}
          </button>
        );
      })}
    </div>
  );
}
