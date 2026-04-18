# TanStack Query Migration & Core Extraction Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate all server state from Zustand to TanStack Query, extract headless business logic to `core/` directory, preparing for monorepo extraction in Phase 6.

**Architecture:** Replace Zustand's dual role (server cache + client state) with TanStack Query for server state (queries + mutations + cache) and Zustand for client-only state (UI selections, filters, drafts). WebSocket events bridge to TanStack Query via `queryClient.setQueryData` / `invalidateQueries`. A new `core/` directory under `apps/web/` acts as the future `packages/core/` incubator.

**Tech Stack:** TanStack Query v5, Zustand v5, React 19, Next.js 16, TypeScript strict mode

---

## Current State Summary

### Stores holding server data (to migrate)
| Store | Server State Fields | API Calls in Store |
|-------|---|---|
| `useAuthStore` | `user` | `getMe`, `sendCode`, `verifyCode` |
| `useWorkspaceStore` | `workspace`, `workspaces[]`, `members[]`, `agents[]`, `skills[]` | `listWorkspaces`, `listMembers`, `listAgents`, `listSkills`, `createWorkspace`, `leaveWorkspace`, `deleteWorkspace` |
| `useIssueStore` | `issues[]` | `listIssues` |
| `useInboxStore` | `items[]` | `listInbox` |
| `useRuntimeStore` | `runtimes[]` | `listRuntimes` |

### Custom hooks with embedded server state (to migrate)
| Hook | State | API Calls |
|---|---|---|
| `useIssueTimeline` | `timeline[]` via useState | `listTimeline`, `createComment`, `updateComment`, `deleteComment`, `addReaction`, `removeReaction` |
| `useIssueReactions` | `reactions[]` via useState | `getIssue`, `addIssueReaction`, `removeIssueReaction` |
| `useIssueSubscribers` | `subscribers[]` via useState | `listIssueSubscribers`, `subscribeToIssue`, `unsubscribeFromIssue` |

### Stores staying as-is (pure client state)
| Store | Purpose |
|---|---|
| `useModalStore` | Which modal is open |
| `useNavigationStore` | Last visited path (persisted) |
| `useIssueSelectionStore` | Multi-select checkbox state |
| `useIssueDraftStore` | New issue form draft (persisted) |
| `useIssuesScopeStore` | "all" / "members" / "agents" filter (persisted) |
| `useIssueViewStore` | Board/list mode, filters, sort (persisted) |
| `myIssuesViewStore` | My-issues view filters (persisted) |

### Files with direct `api.*` mutation calls (25+ files)
These will be migrated to use `useMutation` hooks from `core/`.

---

## Target Directory Structure (after Phase 5)

```
apps/web/
├── app/                              # Routing layer (unchanged)
├── core/                             # NEW: headless business logic
│   ├── api/                          # ApiClient, WSClient (moved from shared/api/)
│   │   ├── client.ts
│   │   ├── ws-client.ts
│   │   └── index.ts
│   ├── types/                        # Domain types (moved from shared/types/)
│   │   ├── issue.ts
│   │   ├── workspace.ts
│   │   ├── agent.ts
│   │   ├── events.ts
│   │   ├── comment.ts
│   │   ├── inbox.ts
│   │   ├── subscriber.ts
│   │   ├── attachment.ts
│   │   ├── activity.ts
│   │   ├── api.ts
│   │   └── index.ts
│   ├── auth/
│   │   └── store.ts                  # Zustand: { user, isLoading } (client-only)
│   ├── workspace/
│   │   ├── queries.ts                # workspaceQueries, memberQueries, agentQueries, skillQueries
│   │   ├── mutations.ts              # useCreateWorkspace, useLeaveWorkspace, useDeleteWorkspace, ...
│   │   └── store.ts                  # Zustand: { currentWorkspaceId } (client-only)
│   ├── issues/
│   │   ├── queries.ts                # issueQueries, timelineQueries, reactionQueries, subscriberQueries
│   │   ├── mutations.ts              # useCreateIssue, useUpdateIssue, useDeleteIssue, useBatchUpdate, ...
│   │   ├── store.ts                  # Zustand: { activeIssueId } (client-only)
│   │   └── config/                   # status.ts, priority.ts (pure data, zero JSX)
│   │       ├── status.ts
│   │       ├── priority.ts
│   │       └── index.ts
│   ├── inbox/
│   │   ├── queries.ts                # inboxQueries (dedup as select transform)
│   │   └── mutations.ts              # useMarkRead, useArchive, useBatchMarkRead, ...
│   ├── runtimes/
│   │   ├── queries.ts                # runtimeQueries, usageQueries, activityQueries
│   │   └── store.ts                  # Zustand: { selectedRuntimeId } (client-only)
│   ├── tasks/
│   │   └── queries.ts                # taskQueries (active task, messages, task runs)
│   ├── settings/
│   │   ├── queries.ts                # tokenQueries
│   │   └── mutations.ts              # useUpdateMe, useCreatePAT, useRevokePAT, ...
│   ├── realtime/
│   │   └── sync.ts                   # WS event → queryClient.setQueryData / invalidateQueries
│   ├── query-client.ts               # QueryClient factory
│   └── logger.ts                     # Logger utility
├── features/                         # Web-specific UI + business components
│   ├── auth/
│   │   ├── initializer.tsx           # AuthInitializer (simplified: no workspace hydration)
│   │   ├── auth-cookie.ts
│   │   └── index.ts
│   ├── workspace/
│   │   ├── hooks.ts                  # useActorName (reads from TQ cache now)
│   │   ├── components/
│   │   └── index.ts
│   ├── issues/
│   │   ├── stores/                   # Client-only stores (view, scope, draft, selection)
│   │   ├── components/               # Board, list, detail, pickers, icons
│   │   ├── utils/                    # filter.ts, sort.ts
│   │   └── index.ts
│   ├── inbox/                        # (store deleted, only re-exports from core)
│   │   └── index.ts
│   ├── editor/                       # Tiptap editor (contains JSX, stays in features)
│   ├── modals/                       # Modal store + registry
│   ├── realtime/
│   │   ├── provider.tsx              # WSProvider (simplified)
│   │   ├── hooks.ts                  # useWSEvent, useWSReconnect
│   │   └── index.ts
│   ├── runtimes/
│   │   ├── components/               # UI components
│   │   └── index.ts
│   ├── skills/                       # Skill management UI
│   ├── my-issues/                    # My-issues page + view store
│   ├── navigation/                   # Navigation store (Next.js specific)
│   └── landing/                      # Landing page (Web only)
├── components/                       # Shared UI (future packages/ui/)
│   ├── ui/                           # ~55 shadcn components
│   ├── common/                       # actor-avatar, emoji-picker, etc.
│   ├── markdown/
│   └── theme-provider.tsx
├── hooks/                            # Generic UI hooks
├── lib/                              # cn() utility
└── shared/                           # DELETED by end of Phase 5
```

---

## Phase 0: Infrastructure Setup

### Task 0.1: Install TanStack Query

**Files:**
- Modify: `apps/web/package.json`

**Step 1: Install packages**

```bash
cd apps/web && pnpm add @tanstack/react-query @tanstack/react-query-devtools
```

**Step 2: Verify installation**

```bash
pnpm typecheck
```
Expected: PASS (no type errors from new deps)

**Step 3: Commit**

```bash
git add apps/web/package.json apps/web/pnpm-lock.yaml ../../pnpm-lock.yaml
git commit -m "chore(web): install @tanstack/react-query and devtools"
```

---

### Task 0.2: Create core/ directory and query client

**Files:**
- Create: `apps/web/core/query-client.ts`

**Step 1: Create query client factory**

```typescript
import { QueryClient } from "@tanstack/react-query";

export function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // WS keeps data fresh — no automatic refetch on window focus
        staleTime: Infinity,
        // Keep unused cache for 10 minutes
        gcTime: 10 * 60 * 1000,
        refetchOnWindowFocus: false,
        refetchOnReconnect: false,
        retry: 1,
      },
      mutations: {
        retry: false,
      },
    },
  });
}
```

Design decisions:
- `staleTime: Infinity` — WebSocket events handle invalidation, no polling needed.
- `gcTime: 10min` — Navigating away from a page and back within 10min uses cache.
- `refetchOnWindowFocus: false` — WS connection already keeps data current.
- Factory function (not singleton) — SSR-safe, each request gets its own client.

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/core/query-client.ts
git commit -m "feat(core): add TanStack Query client factory"
```

---

### Task 0.3: Add tsconfig path alias for @core/

**Files:**
- Modify: `apps/web/tsconfig.json`

**Step 1: Add path alias**

Add to `compilerOptions.paths`:
```json
{
  "paths": {
    "@/*": ["./*"],
    "@core/*": ["./core/*"]
  }
}
```

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/tsconfig.json
git commit -m "chore(web): add @core/* tsconfig path alias"
```

---

### Task 0.4: Add QueryClientProvider to root layout

**Files:**
- Create: `apps/web/core/provider.tsx`
- Modify: `apps/web/app/layout.tsx`

**Step 1: Create provider component**

```typescript
"use client";

import { useState } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { createQueryClient } from "@core/query-client";

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [client] = useState(createQueryClient);
  return (
    <QueryClientProvider client={client}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

**Step 2: Wrap root layout**

In `apps/web/app/layout.tsx`, add `QueryProvider` inside `ThemeProvider`, wrapping everything:

```tsx
import { QueryProvider } from "@core/provider";

// In the JSX:
<ThemeProvider>
  <QueryProvider>
    <AuthInitializer>
      <WSProvider>{children}</WSProvider>
    </AuthInitializer>
    <ModalRegistry />
    <Toaster />
  </QueryProvider>
</ThemeProvider>
```

**Step 3: Run typecheck and dev server**

```bash
pnpm typecheck
pnpm dev:web  # Verify app loads, check devtools panel appears
```

**Step 4: Commit**

```bash
git add apps/web/core/provider.tsx apps/web/app/layout.tsx
git commit -m "feat(core): add QueryClientProvider to root layout"
```

---

### Task 0.5: Create useWorkspaceId utility hook

**Files:**
- Create: `apps/web/core/hooks.ts`

**Step 1: Create hook**

This hook reads the current workspace ID from the workspace store. All query keys will use this to scope data per workspace.

```typescript
import { useWorkspaceStore } from "@/features/workspace";

/**
 * Returns the current workspace ID.
 * All workspace-scoped queries should use this in their query key.
 */
export function useWorkspaceId(): string | null {
  return useWorkspaceStore((s) => s.workspace?.id ?? null);
}
```

Note: During Phase 3 (workspace migration), this will read from `core/workspace/store.ts` instead. For now it bridges to the existing store.

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/core/hooks.ts
git commit -m "feat(core): add useWorkspaceId utility hook"
```

---

## Phase 1: Issues Migration

> The issues domain is the largest and most complex. It validates all patterns (queries, mutations, optimistic updates, WS sync, cache management) that the other domains will follow.

### Task 1.1: Create issue query key factory and queryOptions

**Files:**
- Create: `apps/web/core/issues/queries.ts`

**Step 1: Write query definitions**

```typescript
import { queryOptions } from "@tanstack/react-query";
import { api } from "@/shared/api";

export const issueKeys = {
  all: ["issues"] as const,
  lists: () => [...issueKeys.all, "list"] as const,
  list: (workspaceId: string | null) =>
    [...issueKeys.lists(), workspaceId] as const,
  details: () => [...issueKeys.all, "detail"] as const,
  detail: (id: string) => [...issueKeys.details(), id] as const,
  timeline: (issueId: string) =>
    [...issueKeys.all, "timeline", issueId] as const,
  reactions: (issueId: string) =>
    [...issueKeys.all, "reactions", issueId] as const,
  subscribers: (issueId: string) =>
    [...issueKeys.all, "subscribers", issueId] as const,
};

export function issueListOptions(workspaceId: string | null) {
  return queryOptions({
    queryKey: issueKeys.list(workspaceId),
    queryFn: () => api.listIssues({ limit: 200 }),
    select: (data) => data.issues,
    enabled: !!workspaceId,
  });
}

export function issueDetailOptions(id: string) {
  return queryOptions({
    queryKey: issueKeys.detail(id),
    queryFn: () => api.getIssue(id),
  });
}

export function issueTimelineOptions(issueId: string) {
  return queryOptions({
    queryKey: issueKeys.timeline(issueId),
    queryFn: () => api.listTimeline(issueId),
  });
}

export function issueReactionsOptions(issueId: string) {
  return queryOptions({
    queryKey: issueKeys.reactions(issueId),
    queryFn: async () => {
      const issue = await api.getIssue(issueId);
      return issue.reactions ?? [];
    },
  });
}

export function issueSubscribersOptions(issueId: string) {
  return queryOptions({
    queryKey: issueKeys.subscribers(issueId),
    queryFn: () => api.listIssueSubscribers(issueId),
  });
}
```

Key design patterns:
- **Query key factory** — Hierarchical keys enable targeted invalidation. `invalidateQueries({ queryKey: issueKeys.all })` invalidates everything; `issueKeys.list(wsId)` only invalidates the list for that workspace.
- **`queryOptions()`** — TanStack Query v5 helper that bundles queryKey + queryFn. Ensures type safety — `useQuery(issueListOptions(wsId))` infers the return type.
- **`enabled: !!workspaceId`** — Don't fetch if no workspace selected (avoids 400s during init).
- **`select`** — Transform response inline. `issueListOptions` unwraps `{ issues: Issue[] }` → `Issue[]`.

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/core/issues/queries.ts
git commit -m "feat(core/issues): add query key factory and queryOptions"
```

---

### Task 1.2: Create issue mutations

**Files:**
- Create: `apps/web/core/issues/mutations.ts`

**Step 1: Write mutation hooks**

```typescript
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/shared/api";
import { issueKeys } from "./queries";
import type { Issue } from "@/shared/types";
import type { CreateIssueRequest, UpdateIssueRequest } from "@/shared/types";

export function useCreateIssue() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateIssueRequest) => api.createIssue(data),
    onSuccess: (newIssue) => {
      // Add to list cache directly (WS event also does this, but local is faster)
      qc.setQueryData<Issue[]>(
        issueKeys.list(newIssue.workspace_id),
        (old) => (old ? [...old, newIssue] : [newIssue]),
      );
    },
  });
}

export function useUpdateIssue() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, ...data }: { id: string } & UpdateIssueRequest) =>
      api.updateIssue(id, data),
    onMutate: async ({ id, ...data }) => {
      // Cancel in-flight fetches for this list
      await qc.cancelQueries({ queryKey: issueKeys.lists() });

      // Snapshot for rollback
      const previousList = qc.getQueriesData<Issue[]>({
        queryKey: issueKeys.lists(),
      });

      // Optimistic update: patch issue in all list caches
      qc.setQueriesData<Issue[]>({ queryKey: issueKeys.lists() }, (old) =>
        old?.map((i) => (i.id === id ? { ...i, ...data } : i)),
      );

      // Also update detail cache if it exists
      qc.setQueryData<Issue>(issueKeys.detail(id), (old) =>
        old ? { ...old, ...data } : old,
      );

      return { previousList };
    },
    onError: (_err, _vars, context) => {
      // Rollback
      if (context?.previousList) {
        for (const [key, data] of context.previousList) {
          if (data) qc.setQueryData(key, data);
        }
      }
    },
    onSettled: (_data, _err, { id }) => {
      // Refetch to ensure consistency
      qc.invalidateQueries({ queryKey: issueKeys.detail(id) });
    },
  });
}

export function useDeleteIssue() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.deleteIssue(id),
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: issueKeys.lists() });
      const previousList = qc.getQueriesData<Issue[]>({
        queryKey: issueKeys.lists(),
      });
      qc.setQueriesData<Issue[]>({ queryKey: issueKeys.lists() }, (old) =>
        old?.filter((i) => i.id !== id),
      );
      qc.removeQueries({ queryKey: issueKeys.detail(id) });
      return { previousList };
    },
    onError: (_err, _id, context) => {
      if (context?.previousList) {
        for (const [key, data] of context.previousList) {
          if (data) qc.setQueryData(key, data);
        }
      }
    },
  });
}

export function useBatchUpdateIssues() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      ids,
      updates,
    }: {
      ids: string[];
      updates: UpdateIssueRequest;
    }) => api.batchUpdateIssues(ids, updates),
    onMutate: async ({ ids, updates }) => {
      await qc.cancelQueries({ queryKey: issueKeys.lists() });
      const previousList = qc.getQueriesData<Issue[]>({
        queryKey: issueKeys.lists(),
      });
      qc.setQueriesData<Issue[]>({ queryKey: issueKeys.lists() }, (old) =>
        old?.map((i) => (ids.includes(i.id) ? { ...i, ...updates } : i)),
      );
      return { previousList };
    },
    onError: (_err, _vars, context) => {
      if (context?.previousList) {
        for (const [key, data] of context.previousList) {
          if (data) qc.setQueryData(key, data);
        }
      }
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: issueKeys.lists() });
    },
  });
}

export function useBatchDeleteIssues() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (ids: string[]) => api.batchDeleteIssues(ids),
    onMutate: async (ids) => {
      await qc.cancelQueries({ queryKey: issueKeys.lists() });
      const previousList = qc.getQueriesData<Issue[]>({
        queryKey: issueKeys.lists(),
      });
      qc.setQueriesData<Issue[]>({ queryKey: issueKeys.lists() }, (old) =>
        old?.filter((i) => !ids.includes(i.id)),
      );
      return { previousList };
    },
    onError: (_err, _ids, context) => {
      if (context?.previousList) {
        for (const [key, data] of context.previousList) {
          if (data) qc.setQueryData(key, data);
        }
      }
    },
  });
}
```

Patterns:
- **Optimistic update with rollback** — `onMutate` saves snapshot, patches cache; `onError` restores snapshot.
- **`setQueriesData` (plural)** — Updates all matching caches (e.g. if two components have different list queries).
- **`onSettled` invalidation** — After mutation completes (success or failure), refetch to sync truth.

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

Note: `CreateIssueRequest` and `UpdateIssueRequest` types may need to be defined or imported. Check `shared/types/api.ts` for existing request types. If they don't exist, define them in the same file or in `shared/types/api.ts`.

**Step 3: Commit**

```bash
git add apps/web/core/issues/mutations.ts
git commit -m "feat(core/issues): add mutation hooks with optimistic updates"
```

---

### Task 1.3: Create issue client-only store

**Files:**
- Create: `apps/web/core/issues/store.ts`

**Step 1: Write minimal client store**

```typescript
import { create } from "zustand";

interface IssueClientState {
  activeIssueId: string | null;
  setActiveIssue: (id: string | null) => void;
}

export const useIssueClientStore = create<IssueClientState>((set) => ({
  activeIssueId: null,
  setActiveIssue: (id) => set({ activeIssueId: id }),
}));
```

This is everything that remains of `useIssueStore` after server state moves to TanStack Query.

**Step 2: Commit**

```bash
git add apps/web/core/issues/store.ts
git commit -m "feat(core/issues): add client-only store for activeIssueId"
```

---

### Task 1.4: Create core/issues/index.ts barrel export

**Files:**
- Create: `apps/web/core/issues/index.ts`

**Step 1: Create barrel**

```typescript
export {
  issueKeys,
  issueListOptions,
  issueDetailOptions,
  issueTimelineOptions,
  issueReactionsOptions,
  issueSubscribersOptions,
} from "./queries";

export {
  useCreateIssue,
  useUpdateIssue,
  useDeleteIssue,
  useBatchUpdateIssues,
  useBatchDeleteIssues,
} from "./mutations";

export { useIssueClientStore } from "./store";
```

**Step 2: Commit**

```bash
git add apps/web/core/issues/index.ts
git commit -m "feat(core/issues): add barrel export"
```

---

### Task 1.5: Migrate issue timeline hook

**Files:**
- Modify: `apps/web/features/issues/hooks/use-issue-timeline.ts`

**Context:** This hook currently manages its own `useState<TimelineEntry[]>` + manual `useEffect` fetching + manual WS subscription. Replace with `useQuery` + `useMutation` from core.

**Step 1: Rewrite hook**

Replace the entire hook to use TanStack Query:
- `useQuery(issueTimelineOptions(issueId))` for initial data + cache
- `useMutation` for `createComment`, `editComment`, `deleteComment`, `toggleReaction`
- `useWSEvent` handlers call `queryClient.setQueryData` to append/update entries
- `useWSReconnect` calls `queryClient.invalidateQueries` (replaces manual refetch)
- Optimistic updates for comment CRUD and reactions

Key changes:
- Remove all `useState` for timeline data
- Remove all `useEffect` for data fetching
- Remove manual WS → setState syncing
- Keep the public API shape the same so consumers don't change

**Step 2: Update consumers**

Check all imports of `useIssueTimeline` — the return type should be compatible. If it previously returned `{ timeline, loading, submitComment, ... }`, the new version should return the same shape.

**Step 3: Run typecheck + test**

```bash
pnpm typecheck
pnpm test
```

**Step 4: Commit**

```bash
git add apps/web/features/issues/hooks/use-issue-timeline.ts
git commit -m "refactor(issues): migrate useIssueTimeline to TanStack Query"
```

---

### Task 1.6: Migrate issue reactions hook

**Files:**
- Modify: `apps/web/features/issues/hooks/use-issue-reactions.ts`

**Step 1: Rewrite hook**

Replace `useState` + `useEffect` + manual fetch with:
- `useQuery(issueReactionsOptions(issueId))`
- `useMutation` for `toggleReaction` (optimistic add/remove in cache)
- WS events `issue_reaction:added` / `issue_reaction:removed` → `queryClient.setQueryData`

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/features/issues/hooks/use-issue-reactions.ts
git commit -m "refactor(issues): migrate useIssueReactions to TanStack Query"
```

---

### Task 1.7: Migrate issue subscribers hook

**Files:**
- Modify: `apps/web/features/issues/hooks/use-issue-subscribers.ts`

**Step 1: Rewrite hook**

Replace with:
- `useQuery(issueSubscribersOptions(issueId))`
- `useMutation` for `toggleSubscriber` (optimistic add/remove)
- WS events `subscriber:added` / `subscriber:removed` → `queryClient.setQueryData`

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/features/issues/hooks/use-issue-subscribers.ts
git commit -m "refactor(issues): migrate useIssueSubscribers to TanStack Query"
```

---

### Task 1.8: Migrate issue list consumers

**Files to update (all read from `useIssueStore`):**
- `apps/web/features/issues/components/issues-page.tsx`
- `apps/web/features/issues/components/board-view.tsx`
- `apps/web/features/issues/components/list-view.tsx`
- `apps/web/features/issues/components/board-card.tsx`
- `apps/web/features/issues/components/batch-action-toolbar.tsx`
- `apps/web/features/my-issues/components/my-issues-page.tsx`

**Step 1: Replace store reads with useQuery**

In each file:
```typescript
// Before
const issues = useIssueStore((s) => s.issues);
const loading = useIssueStore((s) => s.loading);

// After
import { useQuery } from "@tanstack/react-query";
import { issueListOptions } from "@core/issues";
import { useWorkspaceId } from "@core/hooks";

const workspaceId = useWorkspaceId();
const { data: issues = [], isLoading: loading } = useQuery(issueListOptions(workspaceId));
```

**Step 2: Replace store mutations with mutation hooks**

In each file that calls `api.updateIssue`, `api.createIssue`, etc.:
```typescript
// Before
await api.updateIssue(id, updates);
useIssueStore.getState().updateIssue(id, updates);

// After
const updateIssue = useUpdateIssue();
await updateIssue.mutateAsync({ id, ...updates });
// Cache is updated automatically via onMutate optimistic update
```

**Step 3: Replace activeIssueId**

```typescript
// Before
const activeIssueId = useIssueStore((s) => s.activeIssueId);
useIssueStore.getState().setActiveIssue(id);

// After
import { useIssueClientStore } from "@core/issues";
const activeIssueId = useIssueClientStore((s) => s.activeIssueId);
useIssueClientStore.getState().setActiveIssue(id);
```

**Step 4: Run typecheck + test**

```bash
pnpm typecheck
pnpm test
```

**Step 5: Commit per file or group**

```bash
git commit -m "refactor(issues): migrate issue list consumers to TanStack Query"
```

---

### Task 1.9: Migrate issue detail component

**Files:**
- Modify: `apps/web/features/issues/components/issue-detail.tsx`

**Step 1: Replace local fetch with useQuery**

```typescript
// Before: useState + useEffect + api.getIssue(id)
// After:
const { data: issue, isLoading } = useQuery(issueDetailOptions(issueId));
```

**Step 2: Replace mutation calls**

```typescript
// Before: api.updateIssue(id, updates) + manual state rollback
// After:
const updateIssue = useUpdateIssue();
const deleteIssue = useDeleteIssue();
// Optimistic update + rollback is handled by the mutation hook
```

**Step 3: Run typecheck**

```bash
pnpm typecheck
```

**Step 4: Commit**

```bash
git commit -m "refactor(issues): migrate issue-detail to TanStack Query"
```

---

### Task 1.10: Migrate create issue modal

**Files:**
- Modify: `apps/web/features/modals/create-issue.tsx`

**Step 1: Replace direct api call with mutation**

```typescript
// Before: const issue = await api.createIssue(data);
// After:
const createIssue = useCreateIssue();
const issue = await createIssue.mutateAsync(data);
```

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git commit -m "refactor(modals): migrate create-issue to useCreateIssue mutation"
```

---

### Task 1.11: Update realtime sync for issues

**Files:**
- Modify: `apps/web/features/realtime/use-realtime-sync.ts`

**Step 1: Replace Zustand store writes with queryClient operations**

```typescript
// Before:
useIssueStore.getState().updateIssue(issue.id, issue);
useIssueStore.getState().addIssue(issue);
useIssueStore.getState().removeIssue(issue_id);

// After:
import { useQueryClient } from "@tanstack/react-query";
import { issueKeys } from "@core/issues";

// In the hook:
const queryClient = useQueryClient();

// issue:updated → patch cache directly
queryClient.setQueryData<Issue[]>(
  issueKeys.list(workspaceId),
  (old) => old?.map((i) => (i.id === issue.id ? { ...i, ...issue } : i)),
);
// Also update detail cache
queryClient.setQueryData<Issue>(
  issueKeys.detail(issue.id),
  (old) => old ? { ...old, ...issue } : old,
);

// issue:created → append to list cache
queryClient.setQueryData<Issue[]>(
  issueKeys.list(workspaceId),
  (old) => old && !old.some((i) => i.id === issue.id) ? [...old, issue] : old,
);

// issue:deleted → remove from list cache
queryClient.setQueryData<Issue[]>(
  issueKeys.list(workspaceId),
  (old) => old?.filter((i) => i.id !== issue_id),
);
queryClient.removeQueries({ queryKey: issueKeys.detail(issue_id) });
```

**Step 2: Replace reconnect handler**

```typescript
// Before:
useIssueStore.getState().fetch();

// After:
queryClient.invalidateQueries({ queryKey: issueKeys.all });
```

Note: Keep the inbox/workspace/agent/member/skill handlers as-is for now. They'll be migrated in Phase 2-4.

**Step 3: Run typecheck**

```bash
pnpm typecheck
```

**Step 4: Commit**

```bash
git commit -m "refactor(realtime): migrate issue WS events to queryClient"
```

---

### Task 1.12: Remove server state from useIssueStore

**Files:**
- Modify: `apps/web/features/issues/store.ts`

**Step 1: Strip server state and methods**

Remove: `issues`, `loading`, `fetch`, `setIssues`, `addIssue`, `updateIssue`, `removeIssue`
Keep: `activeIssueId`, `setActiveIssue`

Or better: delete the file entirely if no one imports `activeIssueId` from it anymore (they should import from `@core/issues`).

**Step 2: Update all remaining imports**

Search for `from "@/features/issues"` that still reference `useIssueStore` for server data. Replace with `@core/issues`.

```bash
# Find all remaining useIssueStore imports
grep -rn "useIssueStore" apps/web/
```

**Step 3: Remove the import from workspace store**

In `apps/web/features/workspace/store.ts`, remove:
```typescript
import { useIssueStore } from "@/features/issues";
// And all calls to useIssueStore.getState().fetch() / setIssues()
```

These are no longer needed — TanStack Query automatically fetches when the workspace ID changes in the query key.

**Step 4: Run full check**

```bash
make check
```

**Step 5: Commit**

```bash
git commit -m "refactor(issues): remove server state from useIssueStore"
```

---

### Task 1.13: Move issues config to core

**Files:**
- Move: `apps/web/features/issues/config/status.ts` → `apps/web/core/issues/config/status.ts`
- Move: `apps/web/features/issues/config/priority.ts` → `apps/web/core/issues/config/priority.ts`
- Create: `apps/web/core/issues/config/index.ts`

**Step 1: Move files**

Move the config files. These are pure data (no JSX, no react-dom), so they belong in core.

**Important:** Only move the data/constants. If these files export React components (like `StatusIcon`), keep the components in `features/issues/components/` and only move the data objects.

**Step 2: Update imports**

```bash
grep -rn "from.*issues/config" apps/web/
```

Replace `@/features/issues/config` with `@core/issues/config` in all consumers.

**Step 3: Run typecheck**

```bash
pnpm typecheck
```

**Step 4: Commit**

```bash
git commit -m "refactor(core/issues): move status/priority config to core"
```

---

## Phase 2: Inbox Migration

### Task 2.1: Create inbox query key factory and queryOptions

**Files:**
- Create: `apps/web/core/inbox/queries.ts`

**Step 1: Write query definitions**

```typescript
import { queryOptions } from "@tanstack/react-query";
import { api } from "@/shared/api";
import type { InboxItem } from "@/shared/types";

export const inboxKeys = {
  all: ["inbox"] as const,
  list: (workspaceId: string | null) =>
    [...inboxKeys.all, "list", workspaceId] as const,
  unreadCount: (workspaceId: string | null) =>
    [...inboxKeys.all, "unread-count", workspaceId] as const,
};

/**
 * Deduplicates inbox items by issue_id, keeping the latest entry.
 * This was previously `useInboxStore.dedupedItems()`.
 */
function deduplicateInboxItems(items: InboxItem[]): InboxItem[] {
  const map = new Map<string, InboxItem>();
  // Sort by created_at DESC first, then dedup keeps first occurrence
  const sorted = [...items].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
  );
  for (const item of sorted) {
    if (!item.archived && !map.has(item.issue_id)) {
      map.set(item.issue_id, item);
    }
  }
  return Array.from(map.values());
}

export function inboxListOptions(workspaceId: string | null) {
  return queryOptions({
    queryKey: inboxKeys.list(workspaceId),
    queryFn: () => api.listInbox(),
    select: deduplicateInboxItems,
    enabled: !!workspaceId,
  });
}

/**
 * Raw inbox items (not deduplicated). Used when you need the full list
 * for batch operations or status updates.
 */
export function inboxRawListOptions(workspaceId: string | null) {
  return queryOptions({
    queryKey: inboxKeys.list(workspaceId),
    queryFn: () => api.listInbox(),
    enabled: !!workspaceId,
  });
}
```

Key: `deduplicateInboxItems` is a `select` transform, so dedup happens on read, not on storage. The raw cache always holds the full list.

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/core/inbox/queries.ts
git commit -m "feat(core/inbox): add query key factory with dedup select transform"
```

---

### Task 2.2: Create inbox mutations

**Files:**
- Create: `apps/web/core/inbox/mutations.ts`

**Step 1: Write mutation hooks**

```typescript
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/shared/api";
import { inboxKeys } from "./queries";
import type { InboxItem } from "@/shared/types";

export function useMarkInboxRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.markInboxRead(id),
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: inboxKeys.all });
      const prev = qc.getQueriesData<InboxItem[]>({ queryKey: inboxKeys.all });
      qc.setQueriesData<InboxItem[]>({ queryKey: inboxKeys.all }, (old) =>
        old?.map((item) => (item.id === id ? { ...item, read: true } : item)),
      );
      return { prev };
    },
    onError: (_err, _id, ctx) => {
      ctx?.prev?.forEach(([key, data]) => { if (data) qc.setQueryData(key, data); });
    },
  });
}

export function useArchiveInbox() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => api.archiveInbox(id),
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: inboxKeys.all });
      const prev = qc.getQueriesData<InboxItem[]>({ queryKey: inboxKeys.all });
      qc.setQueriesData<InboxItem[]>({ queryKey: inboxKeys.all }, (old) =>
        old?.map((item) => (item.id === id ? { ...item, archived: true } : item)),
      );
      return { prev };
    },
    onError: (_err, _id, ctx) => {
      ctx?.prev?.forEach(([key, data]) => { if (data) qc.setQueryData(key, data); });
    },
  });
}

export function useMarkAllInboxRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.markAllInboxRead(),
    onMutate: async () => {
      await qc.cancelQueries({ queryKey: inboxKeys.all });
      const prev = qc.getQueriesData<InboxItem[]>({ queryKey: inboxKeys.all });
      qc.setQueriesData<InboxItem[]>({ queryKey: inboxKeys.all }, (old) =>
        old?.map((item) => (item.archived ? item : { ...item, read: true })),
      );
      return { prev };
    },
    onError: (_err, _vars, ctx) => {
      ctx?.prev?.forEach(([key, data]) => { if (data) qc.setQueryData(key, data); });
    },
  });
}

export function useArchiveAllInbox() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.archiveAllInbox(),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: inboxKeys.all });
    },
  });
}

export function useArchiveAllReadInbox() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.archiveAllReadInbox(),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: inboxKeys.all });
    },
  });
}
```

**Step 2: Run typecheck**

```bash
pnpm typecheck
```

**Step 3: Commit**

```bash
git add apps/web/core/inbox/mutations.ts
git commit -m "feat(core/inbox): add inbox mutation hooks"
```

---

### Task 2.3: Create inbox barrel + migrate consumers + update WS sync + delete store

**Files:**
- Create: `apps/web/core/inbox/index.ts`
- Modify: `apps/web/app/(dashboard)/inbox/page.tsx` — replace `useInboxStore` reads + `api.*` calls
- Modify: `apps/web/features/realtime/use-realtime-sync.ts` — replace inbox store writes
- Modify: `apps/web/features/workspace/store.ts` — remove `useInboxStore.getState().fetch()`
- Modify: `apps/web/features/inbox/store.ts` — delete or gut

**Step 1: Create barrel**

```typescript
export { inboxKeys, inboxListOptions, inboxRawListOptions } from "./queries";
export {
  useMarkInboxRead,
  useArchiveInbox,
  useMarkAllInboxRead,
  useArchiveAllInbox,
  useArchiveAllReadInbox,
} from "./mutations";
```

**Step 2: Migrate inbox page**

Replace all `useInboxStore` reads with `useQuery(inboxListOptions(workspaceId))`.
Replace all `api.markInboxRead()`, `api.archiveInbox()` etc. with mutation hooks.

**Step 3: Update WS sync**

```typescript
// Before:
useInboxStore.getState().addItem(item);

// After:
queryClient.setQueryData<InboxItem[]>(
  inboxKeys.list(workspaceId),
  (old) => old && !old.some((i) => i.id === item.id) ? [item, ...old] : old,
);
```

**Step 4: Remove inbox fetch from workspace store**

In `workspace/store.ts` remove: `useInboxStore.getState().fetch().catch(() => {})` from `hydrateWorkspace`.

**Step 5: Delete inbox store server state**

Delete `apps/web/features/inbox/store.ts` if nothing else uses it.

**Step 6: Run full check**

```bash
make check
```

**Step 7: Commit**

```bash
git commit -m "refactor(inbox): migrate to TanStack Query, delete useInboxStore"
```

---

## Phase 3: Workspace Migration

### Task 3.1: Create workspace query key factory and queryOptions

**Files:**
- Create: `apps/web/core/workspace/queries.ts`

```typescript
import { queryOptions } from "@tanstack/react-query";
import { api } from "@/shared/api";

export const workspaceKeys = {
  all: ["workspaces"] as const,
  list: () => [...workspaceKeys.all, "list"] as const,
  detail: (id: string) => [...workspaceKeys.all, "detail", id] as const,
  members: (workspaceId: string) =>
    [...workspaceKeys.all, "members", workspaceId] as const,
  agents: (workspaceId: string) =>
    [...workspaceKeys.all, "agents", workspaceId] as const,
  skills: (workspaceId: string | null) =>
    [...workspaceKeys.all, "skills", workspaceId] as const,
};

export function workspaceListOptions() {
  return queryOptions({
    queryKey: workspaceKeys.list(),
    queryFn: () => api.listWorkspaces(),
  });
}

export function memberListOptions(workspaceId: string | null) {
  return queryOptions({
    queryKey: workspaceKeys.members(workspaceId!),
    queryFn: () => api.listMembers(workspaceId!),
    enabled: !!workspaceId,
  });
}

export function agentListOptions(workspaceId: string | null) {
  return queryOptions({
    queryKey: workspaceKeys.agents(workspaceId!),
    queryFn: () =>
      api.listAgents({ workspace_id: workspaceId!, include_archived: true }),
    enabled: !!workspaceId,
  });
}

export function skillListOptions(workspaceId: string | null) {
  return queryOptions({
    queryKey: workspaceKeys.skills(workspaceId),
    queryFn: () => api.listSkills(),
    enabled: !!workspaceId,
  });
}
```

---

### Task 3.2: Create workspace mutations

**Files:**
- Create: `apps/web/core/workspace/mutations.ts`

Includes: `useCreateWorkspace`, `useUpdateWorkspace`, `useLeaveWorkspace`, `useDeleteWorkspace`, member CRUD mutations, agent CRUD mutations, skill CRUD mutations.

---

### Task 3.3: Create workspace client store

**Files:**
- Create: `apps/web/core/workspace/store.ts`

```typescript
import { create } from "zustand";
import { api } from "@/shared/api";

interface WorkspaceClientState {
  currentWorkspaceId: string | null;
  setCurrentWorkspaceId: (id: string | null) => void;
}

export const useWorkspaceClientStore = create<WorkspaceClientState>((set) => ({
  currentWorkspaceId: localStorage.getItem("statica_workspace_id"),
  setCurrentWorkspaceId: (id) => {
    if (id) {
      localStorage.setItem("statica_workspace_id", id);
      api.setWorkspaceId(id);
    } else {
      localStorage.removeItem("statica_workspace_id");
      api.setWorkspaceId(null);
    }
    set({ currentWorkspaceId: id });
  },
}));
```

This replaces the workspace selection logic from the old `useWorkspaceStore`. The actual workspace data (name, settings, etc.) comes from `useQuery(workspaceListOptions())`.

---

### Task 3.4: Migrate workspace consumers + simplify AuthInitializer

**Key change:** Delete `hydrateWorkspace()`. The old orchestration:

```
hydrateWorkspace() → api.listMembers + api.listAgents + api.listSkills + issueStore.fetch + inboxStore.fetch
```

Becomes: Nothing. Each component calls `useQuery(memberListOptions(workspaceId))` etc. When `workspaceId` changes, all queries with that key automatically refetch.

**AuthInitializer simplification:**
```typescript
// Before: api.getMe() → api.listWorkspaces() → hydrateWorkspace(wsList, preferredId)
// After:  api.getMe() → set user → set currentWorkspaceId (TQ handles the rest)
```

---

### Task 3.5: Update workspace switch logic

**Before:** Manual cross-store clearing + rehydration
**After:** Just change `currentWorkspaceId` in the client store. TanStack Query sees new key → refetch. Optionally `removeQueries` for the old workspace to free memory.

```typescript
function switchWorkspace(newId: string) {
  const oldId = useWorkspaceClientStore.getState().currentWorkspaceId;
  useWorkspaceClientStore.getState().setCurrentWorkspaceId(newId);

  // Remove old workspace cache to free memory
  if (oldId) {
    queryClient.removeQueries({ queryKey: issueKeys.list(oldId) });
    queryClient.removeQueries({ queryKey: inboxKeys.list(oldId) });
    queryClient.removeQueries({ queryKey: workspaceKeys.members(oldId) });
    queryClient.removeQueries({ queryKey: workspaceKeys.agents(oldId) });
  }
}
```

---

### Task 3.6: Update WS sync for workspace/member/agent/skill events

Replace all `useWorkspaceStore.getState().refreshMembers()` etc. with `queryClient.invalidateQueries()`.

---

### Task 3.7: Delete old useWorkspaceStore server state

Strip `members[]`, `agents[]`, `skills[]`, `workspace`, `workspaces[]`, and all refresh/hydrate methods. Or delete entirely if fully migrated.

---

### Task 3.8: Update useWorkspaceId hook

```typescript
// Before (bridging):
import { useWorkspaceStore } from "@/features/workspace";
export function useWorkspaceId() {
  return useWorkspaceStore((s) => s.workspace?.id ?? null);
}

// After:
import { useWorkspaceClientStore } from "@core/workspace/store";
export function useWorkspaceId() {
  return useWorkspaceClientStore((s) => s.currentWorkspaceId);
}
```

---

### Task 3.9: Update useActorName hook

```typescript
// Before: reads members/agents from useWorkspaceStore
// After: reads from TanStack Query cache
import { useQuery } from "@tanstack/react-query";
import { memberListOptions, agentListOptions } from "@core/workspace/queries";

export function useActorName() {
  const workspaceId = useWorkspaceId();
  const { data: members = [] } = useQuery(memberListOptions(workspaceId));
  const { data: agents = [] } = useQuery(agentListOptions(workspaceId));
  // ... same logic, different data source
}
```

**Run full check after Phase 3:**

```bash
make check
```

---

## Phase 4: Runtimes Migration

### Task 4.1: Create runtime queries + store + migrate

**Files:**
- Create: `apps/web/core/runtimes/queries.ts`
- Create: `apps/web/core/runtimes/store.ts` — `{ selectedRuntimeId }` only
- Modify: `apps/web/features/runtimes/store.ts` — delete server state
- Modify: `apps/web/features/runtimes/components/runtimes-page.tsx`
- Modify: `apps/web/features/realtime/use-realtime-sync.ts` — runtime events

```typescript
// core/runtimes/queries.ts
export const runtimeKeys = {
  all: ["runtimes"] as const,
  list: (workspaceId: string | null) =>
    [...runtimeKeys.all, "list", workspaceId] as const,
  usage: (runtimeId: string, days?: number) =>
    [...runtimeKeys.all, "usage", runtimeId, days] as const,
  activity: (runtimeId: string) =>
    [...runtimeKeys.all, "activity", runtimeId] as const,
};
```

---

### Task 4.2: Create task queries

**Files:**
- Create: `apps/web/core/tasks/queries.ts`

For agent-live-card.tsx which fetches `getActiveTaskForIssue`, `listTaskMessages`, `listTasksByIssue`.

---

## Phase 5: Remaining Extraction + Cleanup

### Task 5.1: Move shared/api/ → core/api/

**Files:**
- Move: `apps/web/shared/api/client.ts` → `apps/web/core/api/client.ts`
- Move: `apps/web/shared/api/ws-client.ts` → `apps/web/core/api/ws-client.ts`
- Move: `apps/web/shared/api/index.ts` → `apps/web/core/api/index.ts`

**Step 1: Move files**

**Step 2: Update ALL imports**

```bash
grep -rn "from.*@/shared/api" apps/web/
```

Replace `@/shared/api` with `@core/api` everywhere.

**Step 3: Run typecheck**

```bash
pnpm typecheck
```

**Step 4: Commit**

```bash
git commit -m "refactor(core): move shared/api/ to core/api/"
```

---

### Task 5.2: Move shared/types/ → core/types/

**Files:**
- Move entire `apps/web/shared/types/` → `apps/web/core/types/`

**Step 1: Move files**

**Step 2: Update ALL imports**

```bash
grep -rn "from.*@/shared/types" apps/web/
```

Replace `@/shared/types` with `@core/types` everywhere.

**Step 3: Run typecheck + commit**

---

### Task 5.3: Move shared/logger.ts → core/logger.ts

---

### Task 5.4: Move auth store to core

**Files:**
- Move: `apps/web/features/auth/store.ts` → `apps/web/core/auth/store.ts`
- Modify: `apps/web/features/auth/initializer.tsx` — update import
- Modify: all `useAuthStore` consumers

The auth store holds `user` (server state) and `isLoading`. In a full migration, `user` would become a TanStack Query query. But since auth is a singleton (not workspace-scoped) and rarely changes, it can stay as Zustand for now. The move to `core/` is purely organizational.

---

### Task 5.5: Extract WS sync to core/realtime/sync.ts

Move the logic from `features/realtime/use-realtime-sync.ts` to `core/realtime/sync.ts`.

The `WSProvider` component (contains JSX for React Context) stays in `features/realtime/provider.tsx`. The sync logic (pure hook, no JSX) moves to core.

---

### Task 5.6: Move data hooks to core

After Tasks 1.5-1.7, the rewritten hooks (`useIssueTimeline`, `useIssueReactions`, `useIssueSubscribers`) are pure TanStack Query hooks with no JSX. Move them:

- `features/issues/hooks/use-issue-timeline.ts` → `core/issues/hooks/use-issue-timeline.ts`
- `features/issues/hooks/use-issue-reactions.ts` → `core/issues/hooks/use-issue-reactions.ts`
- `features/issues/hooks/use-issue-subscribers.ts` → `core/issues/hooks/use-issue-subscribers.ts`

---

### Task 5.7: Move shared/hooks/use-file-upload.ts to core

---

### Task 5.8: Delete shared/ directory

Verify nothing imports from `@/shared/`:

```bash
grep -rn "from.*@/shared" apps/web/
```

If clean, delete `apps/web/shared/`.

---

### Task 5.9: Create settings queries + mutations

**Files:**
- Create: `apps/web/core/settings/queries.ts` — `tokenQueries` for PAT list
- Create: `apps/web/core/settings/mutations.ts` — `useUpdateMe`, `useCreatePAT`, `useRevokePAT`, member CRUD if not already in workspace mutations

Migrate:
- `apps/web/app/(dashboard)/settings/_components/account-tab.tsx`
- `apps/web/app/(dashboard)/settings/_components/members-tab.tsx`
- `apps/web/app/(dashboard)/settings/_components/workspace-tab.tsx`
- `apps/web/app/(dashboard)/settings/_components/repositories-tab.tsx`
- `apps/web/app/(dashboard)/settings/_components/tokens-tab.tsx`

---

### Task 5.10: Final verification

**Run full check:**

```bash
make check
```

**Verify success criteria:**

```bash
# Zero Zustand stores with server data
grep -rn "api\." apps/web/features/*/store.ts apps/web/features/*/stores/*.ts
# Should return nothing (no API calls in stores)

# All server data via TQ hooks
grep -rn "useQuery\|useMutation" apps/web/core/
# Should return many hits

# No direct api.* in features/ (except editor file upload which is OK)
grep -rn "api\.\(get\|list\|create\|update\|delete\|batch\|mark\|archive\)" apps/web/features/ apps/web/app/
# Should return nothing or only edge cases

# core/ has zero react-dom imports
grep -rn "react-dom" apps/web/core/
# Should return nothing

# core/ has zero JSX
grep -rn "tsx" apps/web/core/ --include="*.tsx"
# Should return nothing (all files should be .ts, not .tsx)

# shared/ directory deleted
ls apps/web/shared/ 2>&1
# Should return "No such file or directory"
```

---

## Appendix A: Query Key Hierarchy

```
["issues"]
  ["issues", "list", workspaceId]
  ["issues", "detail", issueId]
  ["issues", "timeline", issueId]
  ["issues", "reactions", issueId]
  ["issues", "subscribers", issueId]

["inbox"]
  ["inbox", "list", workspaceId]
  ["inbox", "unread-count", workspaceId]

["workspaces"]
  ["workspaces", "list"]
  ["workspaces", "detail", workspaceId]
  ["workspaces", "members", workspaceId]
  ["workspaces", "agents", workspaceId]
  ["workspaces", "skills", workspaceId]

["runtimes"]
  ["runtimes", "list", workspaceId]
  ["runtimes", "usage", runtimeId, days]
  ["runtimes", "activity", runtimeId]

["tasks"]
  ["tasks", "active", issueId]
  ["tasks", "messages", taskId]
  ["tasks", "runs", issueId]

["tokens"]
  ["tokens", "list"]
```

---

## Appendix B: WS Event → TanStack Query Mapping

| WS Event | TQ Operation | Key |
|---|---|---|
| `issue:created` | `setQueryData` (append) | `issueKeys.list(wsId)` |
| `issue:updated` | `setQueryData` (patch) | `issueKeys.list(wsId)` + `issueKeys.detail(id)` |
| `issue:deleted` | `setQueryData` (filter) + `removeQueries` | `issueKeys.list(wsId)` + `issueKeys.detail(id)` |
| `comment:created` | `setQueryData` (append) | `issueKeys.timeline(issueId)` |
| `comment:updated` | `setQueryData` (patch) | `issueKeys.timeline(issueId)` |
| `comment:deleted` | `setQueryData` (filter) | `issueKeys.timeline(issueId)` |
| `activity:created` | `setQueryData` (append) | `issueKeys.timeline(issueId)` |
| `reaction:added/removed` | `setQueryData` (patch) | `issueKeys.timeline(issueId)` |
| `issue_reaction:added/removed` | `setQueryData` (patch) | `issueKeys.reactions(issueId)` |
| `subscriber:added/removed` | `setQueryData` (patch) | `issueKeys.subscribers(issueId)` |
| `inbox:new` | `setQueryData` (prepend) | `inboxKeys.list(wsId)` |
| `inbox:read/archived/batch-*` | `invalidateQueries` | `inboxKeys.all` |
| `member:added/updated/removed` | `invalidateQueries` | `workspaceKeys.members(wsId)` |
| `agent:*` | `invalidateQueries` | `workspaceKeys.agents(wsId)` |
| `skill:*` | `invalidateQueries` | `workspaceKeys.skills(wsId)` |
| `workspace:updated` | `invalidateQueries` | `workspaceKeys.list()` |
| `workspace:deleted` | `invalidateQueries` + side effect | `workspaceKeys.list()` |
| `daemon:register` | `invalidateQueries` | `runtimeKeys.list(wsId)` |
| **Reconnect** | `invalidateQueries` | All keys |

---

## Appendix C: Future Phase 6-7 Reference

This plan intentionally structures `core/` to be easily extractable to `packages/core/` in Phase 6:

1. **`core/` has zero `react-dom` dependency** — Desktop (Electron renderer) can import it directly.
2. **`core/` has zero Next.js dependency** — No `next/navigation`, `next/link`, etc.
3. **`core/` exports only `.ts` files** — No JSX, no components.
4. **Import alias `@core/*`** — In Phase 6, change tsconfig to point `@statica/core/*` to `packages/core/`, or use package.json workspace imports.

The Phase 6 extraction is essentially:
```bash
mv apps/web/core/ packages/core/
# Update tsconfig aliases and package.json
```

Similarly, `components/ui/` + `components/common/` + `hooks/` + `lib/` will become `packages/ui/` in Phase 6.
