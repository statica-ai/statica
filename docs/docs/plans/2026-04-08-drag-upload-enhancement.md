# Drag & Drop Upload Enhancement — Revised Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean drag-and-drop upload with visual feedback. Images render inline, non-images show as file cards. No file type restrictions (match Linear). No separate attachment section (URLs live in markdown).

**Architecture:** Frontend-only. Images use existing `![](url)` markdown. Non-images use `[name](url)` markdown, rendered as a styled card via Tiptap NodeView when URL matches our CDN. Backend unchanged.

**Tech Stack:** Tiptap ProseMirror, React, Tailwind CSS, shadcn tokens

---

## What We Keep (from previous work)

- **Drag overlay** — `content-editor.tsx` drag handlers + `content-editor.css` overlay styles
- **Image upload flow** — blob preview → upload → replace with real URL (existing `file-upload.ts`)
- **Non-image upload placeholder** — `⏳ Uploading filename...` → replaced with link (existing `file-upload.ts`)
- **`MAX_FILE_SIZE`** — 100MB limit

## What We Remove (redundant)

| File | What to remove |
|------|----------------|
| `attachment-section.tsx` | **Delete entire file** |
| `issue-detail.tsx` | attachment query, delete mutation, handleImageRemoved, AttachmentSection JSX, onImageRemoved prop, all `["attachments"]` cache invalidation, onUploadSuccess on CommentInput, `api` import (if unused after) |
| `content-editor.tsx` | `onImageRemoved` prop, `onImageRemovedRef` |
| `extensions/index.ts` | `onImageRemovedRef` option |
| `extensions/file-upload.ts` | `collectImageSrcs`, `imageRemovalTracker` plugin, `isAllowedFileType` check + import, `toast` import |
| `shared/constants/upload.ts` | Everything except `MAX_FILE_SIZE` — remove `ALLOWED_MIME_PATTERNS`, `FILE_INPUT_ACCEPT`, `EXTENSION_MIME_MAP`, `isAllowedFileType`, `matchesMimePattern` |
| `shared/constants/__tests__/upload.test.ts` | All tests except MAX_FILE_SIZE |
| `shared/hooks/use-file-upload.ts` | `isAllowedFileType` import + check |
| `components/common/file-upload-button.tsx` | `FILE_INPUT_ACCEPT` import + `accept` attribute |
| `comment-input.tsx` | `onUploadSuccess` prop |

## What We Add (new)

**File Card Node** — a Tiptap custom node that renders `[name](url)` as a styled card when the URL matches our CDN (`statica-static.copilothub.ai` or S3 bucket domain).

```
Editor view:        ┌──────────────────────────┐
                    │ 📄 report.pdf         ⬇  │
                    └──────────────────────────┘

Markdown storage:   [report.pdf](https://statica-static.copilothub.ai/xxx.pdf)
```

- Only for non-image CDN URLs (images stay as `![](url)`)
- Regular external links (github.com, etc.) stay as normal links
- Card shows: file type icon + filename + download button
- Readonly mode shows the same card

---

## Task 1: Remove Redundant Code

**Files to modify:**
- Delete: `apps/web/features/issues/components/attachment-section.tsx`
- Modify: `apps/web/features/issues/components/issue-detail.tsx`
- Modify: `apps/web/features/issues/components/comment-input.tsx`
- Modify: `apps/web/features/editor/content-editor.tsx`
- Modify: `apps/web/features/editor/extensions/index.ts`
- Modify: `apps/web/features/editor/extensions/file-upload.ts`
- Modify: `apps/web/shared/constants/upload.ts`
- Modify: `apps/web/shared/constants/__tests__/upload.test.ts`
- Modify: `apps/web/shared/hooks/use-file-upload.ts`
- Modify: `apps/web/components/common/file-upload-button.tsx`

**What to do:**
1. Delete `attachment-section.tsx`
2. `issue-detail.tsx`: Remove AttachmentSection import, attachment useQuery, deleteAttachment useMutation, handleImageRemoved, onImageRemoved prop, all `["attachments"]` invalidation in handleDescriptionUpload (revert to simple `uploadWithToast` call), remove onUploadSuccess from CommentInput
3. `comment-input.tsx`: Remove `onUploadSuccess` prop
4. `content-editor.tsx`: Remove `onImageRemoved` prop + ref + wiring
5. `extensions/index.ts`: Remove `onImageRemovedRef` from interface + call
6. `extensions/file-upload.ts`: Remove `collectImageSrcs`, `imageRemovalTracker` plugin, `onImageRemovedRef` param, `isAllowedFileType` import + check, `toast` import (keep `toast` if still used — check)
7. `shared/constants/upload.ts`: Keep only `MAX_FILE_SIZE`. Delete everything else.
8. `shared/constants/__tests__/upload.test.ts`: Keep only `MAX_FILE_SIZE` test
9. `shared/hooks/use-file-upload.ts`: Remove `isAllowedFileType` import + check. Import `MAX_FILE_SIZE` stays.
10. `file-upload-button.tsx`: Remove `FILE_INPUT_ACCEPT` import + `accept` attribute

**Verification:**
```bash
pnpm typecheck && pnpm test
```

**Commit:** `refactor(upload): remove attachment section and file type whitelist`

---

## Task 2: File Card Tiptap Node

**Files:**
- Create: `apps/web/features/editor/extensions/file-card.ts`
- Create: `apps/web/features/editor/extensions/file-card-view.tsx`
- Modify: `apps/web/features/editor/extensions/index.ts`
- Modify: `apps/web/features/editor/content-editor.css`

**Design:**

The node intercepts markdown links `[name](url)` where URL matches our CDN, and renders them as a card NodeView.

```typescript
// Detection: URL starts with CDN domain or known S3 bucket pattern
function isCdnFileUrl(url: string): boolean {
  try {
    const u = new URL(url);
    return u.hostname.endsWith('.copilothub.ai') || u.hostname.endsWith('.amazonaws.com');
  } catch {
    return false;
  }
}

// Only match non-image files (images stay as ![](url))
function isFileCardLink(url: string): boolean {
  return isCdnFileUrl(url) && !isImageUrl(url);
}
```

**Node spec:**
- Node name: `fileCard`
- Attrs: `href`, `filename`
- Markdown serialize: `[filename](href)`
- Markdown parse: detect `[text](cdnUrl)` where cdnUrl is non-image CDN link
- NodeView: React component with file icon + name + download button

**Card UI (React NodeView):**
```tsx
<div className="file-card">
  <FileText className="h-4 w-4 text-muted-foreground" />
  <span className="truncate text-sm">{filename}</span>
  <a href={href} download={filename} className="...">
    <Download className="h-3.5 w-3.5" />
  </a>
</div>
```

**CSS:**
```css
.file-card {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.375rem 0.75rem;
  border: 1px solid hsl(var(--border));
  border-radius: var(--radius);
  background: hsl(var(--accent) / 0.1);
  margin: 0.25rem 0;
  max-width: 100%;
}
```

**Verification:**
```bash
pnpm typecheck && pnpm test
```

Manual:
1. Upload a PDF → card appears in editor (not plain link)
2. Upload a .go file → card appears
3. Upload an image → still renders inline (not as card)
4. Paste an external link → still renders as normal link (not card)
5. Save and reload → card still displays correctly
6. Switch to readonly mode → card still displays

**Commit:** `feat(editor): render CDN file links as styled cards`

---

## Task 3: Update Non-Image Upload to Use File Card

**Files:**
- Modify: `apps/web/features/editor/extensions/file-upload.ts`

Currently the non-image upload path inserts a markdown string `[name](url)`. After Task 2 adds the fileCard node, this should insert a `fileCard` node directly instead:

```typescript
// Instead of:
const linkText = `[${result.filename}](${result.link})`;
replacePlaceholder(editor, placeholder, linkText);

// Insert fileCard node:
replacePlaceholder(editor, placeholder, "");
editor.chain().focus().insertContent({
  type: "fileCard",
  attrs: { href: result.link, filename: result.filename },
}).run();
```

**Verification:**
```bash
pnpm typecheck && pnpm test
```

Manual: Upload a PDF → placeholder appears → replaced with file card (not plain text link)

**Commit:** `feat(upload): insert file card node for non-image uploads`

---

## Task 4: Full Verification

```bash
pnpm typecheck && pnpm test
```

Manual test all upload flows:
1. Drag image → overlay → drop → inline image with pulse → real image
2. Drag PDF → overlay → drop → placeholder → file card
3. Drag .mp4 → uploads normally (no type restriction) → file card
4. Paste image → inline image
5. Click 📎 → file picker shows all types → upload works
6. Readonly mode → cards and images display correctly
7. Save → reload → everything persists

**Commit:** fix any issues found

---

## Expected Outcome

| Before (current) | After |
|-------------------|-------|
| File type whitelist blocks .mp4/.zip/etc | All files accepted (like Linear) |
| Attachment Section below description | Gone — files live in markdown |
| Non-image files as plain `[name](url)` text | Styled file card with icon + download |
| Image removal tracker + attachment cache | Gone — simpler code |
| ~300 lines of attachment UI code | Deleted |
| ~100 lines of whitelist code | Replaced by 1 line: `MAX_FILE_SIZE` |
