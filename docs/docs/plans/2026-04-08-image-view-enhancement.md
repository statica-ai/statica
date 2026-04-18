# Image View Enhancement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add image hover toolbar (view/download/copy image/copy link/delete), lightbox preview, and smart sizing (centered, max-width capped) — matching Linear's image UX.

**Architecture:** Convert the Image extension from default `<img>` rendering to a React NodeView (`image-view.tsx`). The NodeView wraps `<img>` in a `<figure>` with a hover toolbar and lightbox portal. CSS handles centering and size cap. No new npm dependencies.

**Tech Stack:** Tiptap `ReactNodeViewRenderer`, lucide-react, sonner (toast), CSS, `createPortal` for lightbox

---

## Task 1: Create Image NodeView Component

**Files:**
- Create: `apps/web/features/editor/extensions/image-view.tsx`

**Step 1: Create the ImageView component**

```tsx
// apps/web/features/editor/extensions/image-view.tsx
"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { NodeViewWrapper } from "@tiptap/react";
import type { NodeViewProps } from "@tiptap/react";
import {
  Maximize2,
  Download,
  Copy,
  Link as LinkIcon,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Lightbox — full-screen image preview (ESC or click backdrop to close)
// ---------------------------------------------------------------------------

function ImageLightbox({
  src,
  alt,
  onClose,
}: {
  src: string;
  alt: string;
  onClose: () => void;
}) {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [onClose]);

  return createPortal(
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 cursor-zoom-out"
      onClick={onClose}
    >
      <img
        src={src}
        alt={alt}
        className="max-h-[90vh] max-w-[90vw] rounded-lg object-contain"
      />
    </div>,
    document.body,
  );
}

// ---------------------------------------------------------------------------
// Image NodeView — renders <img> with hover toolbar + lightbox
// ---------------------------------------------------------------------------

function ImageView({ node, editor, selected, deleteNode }: NodeViewProps) {
  const src = node.attrs.src as string;
  const alt = (node.attrs.alt as string) || "";
  const title = node.attrs.title as string | undefined;
  const uploading = node.attrs.uploading as boolean;

  const [lightbox, setLightbox] = useState(false);
  const isEditable = editor.isEditable;

  const handleView = () => setLightbox(true);

  const handleDownload = async () => {
    try {
      const res = await fetch(src);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = alt || "image";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch {
      window.open(src, "_blank", "noopener,noreferrer");
    }
  };

  const handleCopyImage = async () => {
    try {
      const res = await fetch(src);
      const blob = await res.blob();
      await navigator.clipboard.write([
        new ClipboardItem({ [blob.type]: blob }),
      ]);
      toast.success("Image copied");
    } catch {
      // Fallback: copy link (Safari doesn't support async clipboard image)
      await navigator.clipboard.writeText(src);
      toast.success("Link copied");
    }
  };

  const handleCopyLink = async () => {
    await navigator.clipboard.writeText(src);
    toast.success("Link copied");
  };

  return (
    <NodeViewWrapper className="image-node">
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
      <figure
        className={cn(
          "image-figure",
          selected && isEditable && "image-selected",
        )}
        contentEditable={false}
        onClick={!isEditable && !uploading ? handleView : undefined}
      >
        <img
          src={src}
          alt={alt}
          title={title || undefined}
          className={cn("image-content", uploading && "image-uploading")}
          draggable={false}
        />
        {!uploading && (
          <div
            className="image-toolbar"
            onMouseDown={(e) => e.stopPropagation()}
            onClick={(e) => e.stopPropagation()}
          >
            <button type="button" onClick={handleView} title="View image">
              <Maximize2 className="size-3.5" />
            </button>
            <button type="button" onClick={handleDownload} title="Download">
              <Download className="size-3.5" />
            </button>
            <button
              type="button"
              onClick={handleCopyImage}
              title="Copy image"
            >
              <Copy className="size-3.5" />
            </button>
            <button
              type="button"
              onClick={handleCopyLink}
              title="Copy link"
            >
              <LinkIcon className="size-3.5" />
            </button>
            {isEditable && (
              <button
                type="button"
                onClick={() => deleteNode()}
                title="Delete"
              >
                <Trash2 className="size-3.5" />
              </button>
            )}
          </div>
        )}
      </figure>
      {lightbox && (
        <ImageLightbox
          src={src}
          alt={alt}
          onClose={() => setLightbox(false)}
        />
      )}
    </NodeViewWrapper>
  );
}

export { ImageView };
```

**Step 2: Verify file created**

Run: `ls apps/web/features/editor/extensions/image-view.tsx`
Expected: file exists

---

## Task 2: Wire Up NodeView in Image Extension

**Files:**
- Modify: `apps/web/features/editor/extensions/index.ts:59-75`

**Step 1: Add import**

At the top of `index.ts`, after the existing imports, add:

```typescript
import { ImageView } from "./image-view";
```

**Step 2: Update ImageExtension — add NodeView, remove inline style**

Replace the `ImageExtension` definition (lines 59-75) with:

```typescript
const ImageExtension = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      uploading: {
        default: false,
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.uploading ? { "data-uploading": "" } : {},
        parseHTML: (el: HTMLElement) => el.hasAttribute("data-uploading"),
      },
    };
  },
  addNodeView() {
    return ReactNodeViewRenderer(ImageView);
  },
}).configure({
  inline: false,
  allowBase64: false,
});
```

Key changes:
- Added `addNodeView()` — images now render via React component
- Removed `HTMLAttributes: { style: "max-width: 100%; height: auto;" }` — sizing is now in CSS

**Step 3: Run typecheck**

Run: `pnpm typecheck`
Expected: PASS

**Step 4: Commit**

```bash
git add apps/web/features/editor/extensions/image-view.tsx apps/web/features/editor/extensions/index.ts
git commit -m "feat(editor): add Image NodeView with toolbar and lightbox

- React NodeView renders images with hover toolbar (view/download/copy/link/delete)
- Lightbox portal for full-screen preview (ESC or click to close)
- Copy image with clipboard API (fallback to copy link on Safari)
- Delete button in edit mode only
- Readonly: click image opens lightbox"
```

---

## Task 3: Update Image CSS — Centering, sizing, toolbar, lightbox

**Files:**
- Modify: `apps/web/features/editor/content-editor.css:379-395`

**Step 1: Replace image CSS rules**

Replace lines 379-395 (from `/* Images — shared styling */` through the `@keyframes` block) with:

```css
/* Images — generic fallback (non-NodeView contexts) */
.rich-text-editor img {
  max-width: 100%;
  height: auto;
  border-radius: var(--radius);
  margin: 0.5rem 0;
}

/* Image NodeView — centered block with max-width cap */
.rich-text-editor .image-node {
  display: block !important;
  text-align: center;
}

.rich-text-editor .image-figure {
  position: relative;
  display: inline-block;
  max-width: min(100%, 640px);
  margin: 0.75rem 0;
}

.rich-text-editor .image-figure.image-selected .image-content {
  outline: 2px solid var(--brand);
  outline-offset: 2px;
}

.rich-text-editor .image-content {
  display: block;
  width: 100%;
  height: auto;
  border-radius: var(--radius);
}

.rich-text-editor .image-uploading {
  opacity: 0.5;
  animation: rte-upload-pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}

@keyframes rte-upload-pulse {
  0%, 100% { opacity: 0.5; }
  50% { opacity: 0.3; }
}

/* Readonly — zoom cursor on clickable images */
.rich-text-editor.readonly .image-figure {
  cursor: zoom-in;
}

/* Image toolbar — dark pill, top-right corner, appears on hover */
.image-toolbar {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
  display: flex;
  gap: 1px;
  padding: 0.25rem;
  background: color-mix(in srgb, black 75%, transparent);
  backdrop-filter: blur(8px);
  border-radius: var(--radius);
  opacity: 0;
  transition: opacity 0.15s;
  z-index: 1;
}

.image-figure:hover .image-toolbar {
  opacity: 1;
}

.image-toolbar button {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.75rem;
  height: 1.75rem;
  border-radius: calc(var(--radius) - 2px);
  color: white;
  transition: background 0.15s;
}

.image-toolbar button:hover {
  background: color-mix(in srgb, white 15%, transparent);
}
```

**Step 2: Run typecheck**

Run: `pnpm typecheck`
Expected: PASS

**Step 3: Commit**

```bash
git add apps/web/features/editor/content-editor.css
git commit -m "style(editor): add image centering, sizing cap, and toolbar styles

- Images centered with max-width 640px cap (smart sizing)
- Dark hover toolbar with blur backdrop
- Selection outline for edit mode
- Zoom cursor for readonly mode
- Upload pulse animation preserved"
```

---

## Task 4: Full Verification

**Step 1: Run all checks**

Run: `pnpm typecheck && pnpm test`
Expected: all pass

**Step 2: Manual verification checklist**

Test in browser:

| # | Test | Expected |
|---|------|----------|
| 1 | Upload large screenshot | Centered, max 640px wide |
| 2 | Upload small image (< 300px) | Natural size, centered |
| 3 | Drag image into editor | Blob preview with pulse → real image |
| 4 | Hover image | Dark toolbar appears top-right (5 buttons edit, 4 readonly) |
| 5 | Toolbar → View image | Full-screen lightbox opens |
| 6 | Lightbox → ESC | Closes |
| 7 | Lightbox → click backdrop | Closes |
| 8 | Toolbar → Download | Browser downloads the image |
| 9 | Toolbar → Copy image | Toast "Image copied", image in clipboard |
| 10 | Toolbar → Copy link | Toast "Link copied", URL in clipboard |
| 11 | Toolbar → Delete | Image removed from editor |
| 12 | Click image (edit mode) | Blue selection outline appears |
| 13 | Select image → Backspace | Image deleted |
| 14 | Click image (readonly mode) | Opens lightbox directly |
| 15 | Readonly toolbar | No Delete button, other 4 buttons work |
| 16 | Save → reload | Images persist with correct styling |

**Step 3: Fix any issues, re-run checks**

Run: `pnpm typecheck && pnpm test`

**Step 4: Commit fixes (if any)**

---

## Architecture Notes

### Why NodeView instead of CSS-only?

The toolbar buttons (view/download/copy/delete) require interactive React components overlaid on the image. CSS-only can handle sizing/centering but cannot add click handlers. A NodeView is the standard Tiptap pattern for this — same as `CodeBlockView` (copy button) and `FileCardView` (download button) already in the codebase.

### Upload flow compatibility

The existing upload flow in `file-upload.ts` uses `tr.setNodeMarkup()` to update image attributes after upload. This works with NodeView because ProseMirror attribute changes trigger React re-renders via `ReactNodeViewRenderer`. Same mechanism used by `FileCardView`'s `finalizeFileCard()`.

### Markdown serialization

No changes needed. Images serialize as `![alt](url)` — standard markdown. The NodeView only affects editor rendering, not serialization. No width/height stored in markdown (sizing is purely CSS).

### Lightbox implementation

Uses `createPortal` to render outside the editor DOM tree, with a keyboard listener for ESC. Intentionally NOT using shadcn Dialog to keep it minimal — no focus trapping or complex accessibility needed for a simple image preview overlay.

### Browser compatibility: Copy image

`navigator.clipboard.write()` with `ClipboardItem` works in Chrome/Edge. Safari requires the clipboard write to be in the same user gesture (no async fetch before write), so it falls back to copying the link URL with a toast notification.

---

## Expected Outcome

| Before | After |
|--------|-------|
| Images stretch to 100% width, left-aligned | Centered, capped at 640px |
| No hover actions on images | 5-button toolbar: View, Download, Copy, Link, Delete |
| No image preview | Click-to-zoom lightbox (ESC/click to close) |
| Readonly images are static | Click to zoom, hover for toolbar (minus Delete) |
| Delete image: select + backspace only | Toolbar Delete button + keyboard |
| No visual selection feedback | Blue outline on selected image |
