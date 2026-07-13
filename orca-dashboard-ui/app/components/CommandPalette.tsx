"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useRouter } from "next/navigation";
import { Search, ShieldCheck, Stethoscope } from "lucide-react";
import { NAV_TABS } from "../lib/nav";

const actions = [
  { id: "doctor", label: "Run Doctor", icon: Stethoscope },
  { id: "policy-check", label: "Policy Check", icon: ShieldCheck },
  { id: "credentials-check", label: "Credentials Check", icon: ShieldCheck },
  { id: "ci-check", label: "CI Check", icon: ShieldCheck },
];

interface CommandPaletteProps {
  isOpen: boolean;
  onClose: () => void;
  onRunAction?: (action: string) => void;
}

export default function CommandPalette({ isOpen, onClose, onRunAction }: CommandPaletteProps) {
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const router = useRouter();

  const views = NAV_TABS.map((tab) => ({
    id: tab.id,
    label: tab.label,
    icon: tab.icon,
    path: tab.href,
  }));

  const allItems = [
    ...views.map((v) => ({ ...v, type: "view" as const })),
    ...actions.map((a) => ({ ...a, type: "action" as const })),
  ].filter((item) => item.label.toLowerCase().includes(query.toLowerCase()));

  useEffect(() => {
    if (isOpen) {
      triggerRef.current = document.activeElement as HTMLElement;
      setQuery("");
      setSelectedIndex(0);
      setTimeout(() => inputRef.current?.focus(), 50);
    } else {
      setTimeout(() => triggerRef.current?.focus(), 0);
    }
  }, [isOpen]);

  useEffect(() => {
    setSelectedIndex(0);
  }, [query]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setSelectedIndex((i) => (i + 1) % allItems.length);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        setSelectedIndex((i) => (i - 1 + allItems.length) % allItems.length);
      } else if (e.key === "Enter") {
        e.preventDefault();
        const item = allItems[selectedIndex];
        if (!item) return;
        if (item.type === "view") {
          router.push(item.path);
          onClose();
        } else if (item.type === "action" && onRunAction) {
          onRunAction(item.id);
          onClose();
        }
      } else if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      } else if (e.key === "Tab") {
        const container = containerRef.current;
        if (!container) return;
        const focusable = container.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        );
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last?.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first?.focus();
        }
      }
    },
    [allItems, selectedIndex, router, onClose, onRunAction]
  );

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-modal flex items-start justify-center bg-black/60 px-4 pt-[12vh] backdrop-blur-sm md:pt-[18vh]"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      role="dialog"
      aria-modal="true"
      aria-label="Command palette"
    >
      <div
        ref={containerRef}
        className="w-full max-w-lg overflow-hidden rounded-xl border border-border bg-surface shadow-2xl"
        onKeyDown={handleKeyDown}
      >
        <div className="flex items-center gap-3 border-b border-border px-4 py-3">
          <Search size={16} className="text-text-tertiary" strokeWidth={1.5} />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search commands and views..."
            className="flex-1 bg-transparent text-[15px] text-text-primary outline-none placeholder:text-text-tertiary"
            aria-label="Command palette search"
          />
          <kbd className="hidden rounded border border-border bg-surface-elevated px-1.5 py-0.5 text-[10px] font-mono text-text-tertiary md:inline-block">
            ESC
          </kbd>
        </div>
        <div className="max-h-[50vh] overflow-auto py-2" role="listbox">
          {allItems.length === 0 && (
            <div className="px-4 py-8 text-center text-sm text-text-tertiary">No results found</div>
          )}
          {allItems.map((item, index) => {
            const Icon = item.icon;
            const isSelected = index === selectedIndex;
            return (
              <button
                key={`${item.type}-${item.id}`}
                role="option"
                aria-selected={isSelected}
                className={`flex w-full items-center gap-3 px-4 py-2.5 text-left text-[13px] transition-colors ${
                  isSelected ? "bg-accent/10 text-text-primary" : "text-text-secondary hover:bg-surface-hover"
                }`}
                onClick={() => {
                  if (item.type === "view") {
                    router.push(item.path);
                    onClose();
                  } else if (item.type === "action" && onRunAction) {
                    onRunAction(item.id);
                    onClose();
                  }
                }}
              >
                <Icon size={15} className="shrink-0" strokeWidth={1.5} />
                <span>{item.label}</span>
                <span className="ml-auto text-[11px] text-text-tertiary capitalize">{item.type}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
