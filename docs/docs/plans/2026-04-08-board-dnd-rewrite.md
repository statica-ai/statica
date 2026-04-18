# Board DnD Rewrite — dnd-kit Multi-Container Sortable

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the Kanban board drag-and-drop to use dnd-kit's multi-container sortable pattern correctly — onDragOver for live cross-column movement, local state during drag, insertion indicators, and smooth animations.

**Architecture:** Replace the current "TQ-cache-driven + pendingMove patch" with a "local-state-driven during drag, TQ sync on drop" model. During drag, a local `columns` state (Record<IssueStatus, string[]>) controls which IDs each SortableContext sees. onDragOver moves IDs between columns in real-time. onDragEnd computes final position and fires the mutation. Between drags, local state follows TQ data via useEffect.

**Tech Stack:** @dnd-kit/core ^6.3.1, @dnd-kit/sortable ^10.0.0, @dnd-kit/utilities ^3.2.2, TanStack Query, React useState

---

## Current State (files to modify)

| File | Current Role | Change |
|------|-------------|--------|
| `features/issues/components/board-view.tsx` | DndContext + onDragEnd only + pendingMove | **Rewrite**: local columns state, onDragOver, onDragEnd, improved DragOverlay |
| `features/issues/components/board-column.tsx` | Receives Issue[], sorts internally, useDroppable | **Rewrite**: receives sorted Issue[] from parent, no internal sorting, insertion indicator |
| `features/issues/components/board-card.tsx` | useSortable with defaults | **Modify**: custom animateLayoutChanges |
| `features/issues/components/issues-page.tsx` | handleMoveIssue callback | **Minor**: adjust callback signature |

Files NOT changed: `mutations.ts`, `ws-updaters.ts`, `use-realtime-sync.ts`, `view-store.ts`, `sort.ts`

---

## Task 1: Rewrite board-view.tsx — Local State + onDragOver + onDragEnd

**Files:**
- Rewrite: `apps/web/features/issues/components/board-view.tsx`

This is the core task. The entire DnD orchestration logic changes.

### Data Model

```typescript
// Local state: maps status → ordered array of issue IDs
// This is the ONLY source of truth for card positions during drag
type Columns = Record<IssueStatus, string[]>;
```

### Step 1: Replace pendingMove with local columns state

Remove `pendingMove` + `displayIssues` + the clearing useEffect. Replace with:

```typescript
// Build columns from TQ issues + view sort settings
function buildColumns(
  issues: Issue[],
  visibleStatuses: IssueStatus[],
  sortBy: SortField,
  sortDirection: SortDirection,
): Columns {
  const cols: Columns = {} as Columns;
  for (const status of visibleStatuses) {
    const sorted = sortIssues(
      issues.filter((i) => i.status === status),
      sortBy,
      sortDirection,
    );
    cols[status] = sorted.map((i) => i.id);
  }
  return cols;
}
```

In the component:

```typescript
const sortBy = useViewStore((s) => s.sortBy);
const sortDirection = useViewStore((s) => s.sortDirection);

// Local columns state — follows TQ between drags, local during drag
const [columns, setColumns] = useState<Columns>(() =>
  buildColumns(issues, visibleStatuses, sortBy, sortDirection)
);
const isDragging = useRef(false);

// Sync from TQ when NOT dragging
useEffect(() => {
  if (!isDragging.current) {
    setColumns(buildColumns(issues, visibleStatuses, sortBy, sortDirection));
  }
}, [issues, visibleStatuses, sortBy, sortDirection]);
```

`issueMap` for O(1) lookup (needed by BoardColumn to get Issue objects from IDs):

```typescript
const issueMap = useMemo(() => {
  const map = new Map<string, Issue>();
  for (const issue of issues) map.set(issue.id, issue);
  return map;
}, [issues]);
```

### Step 2: Implement findColumn helper

```typescript
/** Find which column (status) contains a given ID (issue or column). */
function findColumn(columns: Columns, id: string, visibleStatuses: IssueStatus[]): IssueStatus | null {
  // Is it a column ID itself?
  if (visibleStatuses.includes(id as IssueStatus)) return id as IssueStatus;
  // Search columns for the item
  for (const [status, ids] of Object.entries(columns)) {
    if (ids.includes(id)) return status as IssueStatus;
  }
  return null;
}
```

### Step 3: Implement onDragStart

```typescript
const handleDragStart = useCallback((event: DragStartEvent) => {
  isDragging.current = true;
  const issue = issueMap.get(event.active.id as string) ?? null;
  setActiveIssue(issue);
}, [issueMap]);
```

### Step 4: Implement onDragOver — the key missing piece

This fires continuously during drag. When the pointer crosses into a different column or hovers over a different card, we move the dragged ID in local state. This makes SortableContext aware of the new item → cards shift to make room.

```typescript
const handleDragOver = useCallback((event: DragOverEvent) => {
  const { active, over } = event;
  if (!over) return;

  const activeId = active.id as string;
  const overId = over.id as string;

  const activeCol = findColumn(columns, activeId, visibleStatuses);
  const overCol = findColumn(columns, overId, visibleStatuses);
  if (!activeCol || !overCol || activeCol === overCol) return;

  // Cross-column move: remove from old column, insert into new column
  setColumns((prev) => {
    const oldIds = prev[activeCol]!.filter((id) => id !== activeId);
    const newIds = [...prev[overCol]!];

    // Insert position: if over a card, insert at that index; if over column, append
    const overIndex = newIds.indexOf(overId);
    const insertIndex = overIndex >= 0 ? overIndex : newIds.length;
    newIds.splice(insertIndex, 0, activeId);

    return { ...prev, [activeCol]: oldIds, [overCol]: newIds };
  });
}, [columns, visibleStatuses]);
```

### Step 5: Implement onDragEnd — persist to server

```typescript
const handleDragEnd = useCallback((event: DragEndEvent) => {
  const { active, over } = event;
  isDragging.current = false;
  setActiveIssue(null);

  if (!over) {
    // Cancelled — reset to TQ state
    setColumns(buildColumns(issues, visibleStatuses, sortBy, sortDirection));
    return;
  }

  const activeId = active.id as string;
  const overId = over.id as string;

  const activeCol = findColumn(columns, activeId, visibleStatuses);
  const overCol = findColumn(columns, overId, visibleStatuses);
  if (!activeCol || !overCol) return;

  // Same column reorder
  if (activeCol === overCol) {
    const ids = columns[activeCol]!;
    const oldIndex = ids.indexOf(activeId);
    const newIndex = ids.indexOf(overId);
    if (oldIndex !== newIndex) {
      const reordered = arrayMove(ids, oldIndex, newIndex);
      setColumns((prev) => ({ ...prev, [activeCol]: reordered }));
    }
  }

  // Compute final position from the local column order
  const finalCol = findColumn(columns, activeId, visibleStatuses);
  if (!finalCol) return;

  // After potential same-col reorder, re-read columns
  // (for same-col we just did setColumns above, but it's async;
  //  however we can compute from the intended final order)
  let finalIds: string[];
  if (activeCol === overCol) {
    const ids = columns[activeCol]!;
    const oldIndex = ids.indexOf(activeId);
    const newIndex = ids.indexOf(overId);
    finalIds = oldIndex !== newIndex ? arrayMove(ids, oldIndex, newIndex) : ids;
  } else {
    finalIds = columns[finalCol]!;
  }

  const newPosition = computePosition(finalIds, activeId, issues);
  const currentIssue = issueMap.get(activeId);

  // Skip if nothing changed
  if (currentIssue && currentIssue.status === finalCol && currentIssue.position === newPosition) return;

  onMoveIssue(activeId, finalCol, newPosition);
}, [columns, issues, visibleStatuses, sortBy, sortDirection, issueMap, onMoveIssue]);
```

### Step 6: Update computePosition to work with ID arrays

The current `computePosition` takes `Issue[]` and a target index. Rewrite to take `string[]` (IDs) + the active ID + the issue map:

```typescript
/** Compute a float position for `activeId` based on its neighbors in `ids`. */
function computePosition(ids: string[], activeId: string, allIssues: Issue[]): number {
  const idx = ids.indexOf(activeId);
  if (idx === -1) return 0;

  const getPos = (id: string) => allIssues.find((i) => i.id === id)?.position ?? 0;

  if (ids.length === 1) return 0;
  if (idx === 0) return getPos(ids[1]!) - 1;
  if (idx === ids.length - 1) return getPos(ids[idx - 1]!) + 1;
  return (getPos(ids[idx - 1]!) + getPos(ids[idx + 1]!)) / 2;
}
```

### Step 7: Update DragOverlay styling

```typescript
<DragOverlay dropAnimation={null}>
  {activeIssue ? (
    <div className="w-[280px] rotate-2 scale-105 cursor-grabbing opacity-90 shadow-lg shadow-black/10">
      <BoardCardContent issue={activeIssue} />
    </div>
  ) : null}
</DragOverlay>
```

Key change: `dropAnimation={null}` prevents the overlay from animating back to origin on drop — the card is already in the right position via local state.

### Step 8: Wire it all together

Pass `columns` + `issueMap` to `BoardColumn` instead of `issues`:

```tsx
{visibleStatuses.map((status) => (
  <BoardColumn
    key={status}
    status={status}
    issueIds={columns[status] ?? []}
    issueMap={issueMap}
  />
))}
```

### Step 9: Run typecheck

Run: `pnpm typecheck`
Expected: May have errors in board-column.tsx (prop changes) — that's Task 2.

### Step 10: Commit

```bash
git add apps/web/features/issues/components/board-view.tsx
git commit -m "refactor(board): rewrite DnD with local state + onDragOver for live cross-column sorting"
```

---

## Task 2: Rewrite board-column.tsx — Receive IDs + issueMap, Add Insertion Indicator

**Files:**
- Rewrite: `apps/web/features/issues/components/board-column.tsx`

### Step 1: Change props from `issues: Issue[]` to `issueIds: string[]` + `issueMap: Map<string, Issue>`

The column no longer does its own sorting — the parent provides IDs in the correct order. The column just resolves IDs to Issue objects and renders them.

```typescript
export function BoardColumn({
  status,
  issueIds,
  issueMap,
}: {
  status: IssueStatus;
  issueIds: string[];
  issueMap: Map<string, Issue>;
}) {
  const cfg = STATUS_CONFIG[status];
  const { setNodeRef, isOver } = useDroppable({ id: status });
  const viewStoreApi = useViewStoreApi();

  // Resolve IDs to Issue objects (IDs are already sorted by parent)
  const resolvedIssues = useMemo(
    () => issueIds.flatMap((id) => {
      const issue = issueMap.get(id);
      return issue ? [issue] : [];
    }),
    [issueIds, issueMap],
  );

  return (
    <div className={`flex w-[280px] shrink-0 flex-col rounded-xl ${cfg.columnBg} p-2`}>
      <div className="mb-2 flex items-center justify-between px-1.5">
        <div className="flex items-center gap-2">
          <span className={`inline-flex items-center gap-1.5 rounded px-2 py-0.5 text-xs font-semibold ${cfg.badgeBg} ${cfg.badgeText}`}>
            <StatusIcon status={status} className="h-3 w-3" inheritColor />
            {cfg.label}
          </span>
          <span className="text-xs text-muted-foreground">
            {issueIds.length}
          </span>
        </div>
        {/* Right: add + menu — keep as-is */}
        <div className="flex items-center gap-1">
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <Button variant="ghost" size="icon-sm" className="rounded-full text-muted-foreground">
                  <MoreHorizontal className="size-3.5" />
                </Button>
              }
            />
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => viewStoreApi.getState().hideStatus(status)}>
                <EyeOff className="size-3.5" />
                Hide column
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Tooltip>
            <TooltipTrigger
              render={
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="rounded-full text-muted-foreground"
                  onClick={() => useModalStore.getState().open("create-issue", { status })}
                >
                  <Plus className="size-3.5" />
                </Button>
              }
            />
            <TooltipContent>Add issue</TooltipContent>
          </Tooltip>
        </div>
      </div>
      <div
        ref={setNodeRef}
        className={`min-h-[200px] flex-1 space-y-2 overflow-y-auto rounded-lg p-1 transition-colors ${
          isOver ? "bg-accent/60" : ""
        }`}
      >
        <SortableContext items={issueIds} strategy={verticalListSortingStrategy}>
          {resolvedIssues.map((issue) => (
            <DraggableBoardCard key={issue.id} issue={issue} />
          ))}
        </SortableContext>
        {issueIds.length === 0 && (
          <p className="py-8 text-center text-xs text-muted-foreground">
            No issues
          </p>
        )}
      </div>
    </div>
  );
}
```

Key changes:
- No more `useViewStore` for sort — parent handles sorting
- No more internal `sortIssues` call
- Uses `issueIds` for SortableContext (already in correct order)
- Count shows `issueIds.length` instead of `issues.length`

### Step 2: Run typecheck

Run: `pnpm typecheck`
Expected: PASS (or errors in issues-page.tsx — Task 4)

### Step 3: Commit

```bash
git add apps/web/features/issues/components/board-column.tsx
git commit -m "refactor(board): BoardColumn receives sorted IDs from parent, no internal sorting"
```

---

## Task 3: Modify board-card.tsx — Custom animateLayoutChanges

**Files:**
- Modify: `apps/web/features/issues/components/board-card.tsx`

### Step 1: Add custom animateLayoutChanges

When a card is dragged across containers, dnd-kit triggers a layout animation on the "entering" card. The default `defaultAnimateLayoutChanges` animates this, causing a jarring jump. We disable animation for the frame when `wasDragging` is true (the card just landed in a new container).

```typescript
import { useSortable, defaultAnimateLayoutChanges } from "@dnd-kit/sortable";
import type { AnimateLayoutChanges } from "@dnd-kit/sortable";

const animateLayoutChanges: AnimateLayoutChanges = (args) => {
  const { isSorting, wasDragging } = args;
  if (isSorting || wasDragging) return false;
  return defaultAnimateLayoutChanges(args);
};
```

Update useSortable call:

```typescript
const {
  attributes,
  listeners,
  setNodeRef,
  transform,
  transition,
  isDragging,
} = useSortable({
  id: issue.id,
  data: { status: issue.status },
  animateLayoutChanges,
});
```

### Step 2: Run typecheck

Run: `pnpm typecheck`
Expected: PASS

### Step 3: Commit

```bash
git add apps/web/features/issues/components/board-card.tsx
git commit -m "refactor(board): custom animateLayoutChanges to prevent jarring cross-column animation"
```

---

## Task 4: Adjust issues-page.tsx — Minor Callback Cleanup

**Files:**
- Modify: `apps/web/features/issues/components/issues-page.tsx`

### Step 1: Update handleMoveIssue

The callback shape stays the same (`issueId, newStatus, newPosition`), but the auto-switch-to-manual-sort logic should move into board-view or stay here. Keep it here for now since it's a view-level concern.

No functional change needed — the `onMoveIssue` prop signature is unchanged. Just verify that `BoardView`'s new props are correct:

```tsx
<BoardView
  issues={issues}
  allIssues={scopedIssues}
  visibleStatuses={visibleStatuses}
  hiddenStatuses={hiddenStatuses}
  onMoveIssue={handleMoveIssue}
/>
```

`BoardView` still receives `issues` (filtered+scoped from TQ) and `onMoveIssue`. The internal state management changes are encapsulated.

### Step 2: Run full typecheck + test

Run: `pnpm typecheck && pnpm test`
Expected: PASS

### Step 3: Commit

```bash
git add apps/web/features/issues/components/issues-page.tsx
git commit -m "refactor(board): verify issues-page props match new BoardView interface"
```

---

## Task 5: Manual QA Checklist

After all code changes, verify these scenarios in the browser:

1. **Same-column reorder**: Drag a card up/down within one column → cards shift to make room during drag → drop → position persists after refresh
2. **Cross-column move**: Drag card from Todo to In Progress → card appears in target column DURING drag → target column cards shift → drop → status + position persist
3. **Drop on empty column**: Drag card to an empty column → card lands there
4. **Cancel drag**: Start dragging, press Escape → card returns to original position, no mutation fired
5. **Rapid sequential drags**: Drag card A, drop, immediately drag card B → no flicker or stale state
6. **WebSocket update during drag**: Have another user change an issue → board updates correctly after drag ends (not during)
7. **Sort mode switch**: Drag should auto-switch to "Manual" sort → verify after drag, sort dropdown shows "Manual"
8. **DragOverlay**: Dragged card should have visible shadow, slight rotation, slight scale up
9. **Hidden columns panel**: Still shows correct counts, "Show column" still works

---

## Summary of Architecture Change

```
BEFORE (broken):
  TQ cache → issues prop → displayIssues (with pendingMove patch) → BoardColumn sorts internally
  onDragEnd → pendingMove + mutate → TQ updates → useEffect clears pendingMove
  Problem: dual optimistic update, fire-and-forget cancelQueries race, no onDragOver

AFTER (correct):
  TQ cache → issues prop → buildColumns() → local columns state (when not dragging)
  onDragStart → isDragging=true, freeze local state
  onDragOver → move IDs between columns in local state → SortableContext sees new items → cards shift
  onDragEnd → compute position from local order → mutate → isDragging=false → TQ catches up → local follows
  Problem: none — single source of truth during drag (local), single source of truth between drags (TQ)
```
