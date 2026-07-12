# Orca Dashboard UI

A Vercel-style dashboard for the Orca local guardrail runtime. Built with Next.js 15, TypeScript, and Tailwind CSS.

## Prerequisites

- Node.js 18+
- The Orca backend must be running on `http://127.0.0.1:7742`

## Installation

```bash
cd orca-dashboard-ui
npm install
```

## Development

```bash
npm run dev
```

The dev server starts on `http://localhost:3000` and proxies API requests to the Orca backend at `http://127.0.0.1:7742`.

> **Note:** The Orca backend (`orca dashboard`) must be running on `localhost:7742` for the dashboard to load data.

## Build

```bash
npm run build
npm start
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` / `Ctrl+K` | Open command palette |
| `Escape` | Close command palette, modals, or expanded output drawer |
| `?` | Show keyboard shortcuts (planned) |

## Browser Requirements

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Architecture

- **Next.js 15 App Router** with client-side data fetching
- **Tailwind CSS** with custom semantic color tokens
- **Geist Sans / Mono** fonts
- **Lucide React** icons
- **Shiki** for syntax highlighting (dynamic import)
- Dark mode only
