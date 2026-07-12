"use client";

import { ToastProvider } from "../hooks/useToast";
import { OutputProvider } from "../hooks/useCommandOutput";

export default function ClientProviders({ children }: { children: React.ReactNode }) {
  return (
    <ToastProvider>
      <OutputProvider>{children}</OutputProvider>
    </ToastProvider>
  );
}
