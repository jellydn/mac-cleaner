# Plan 008: Docs hygiene + first-commit checklist (stale planning map)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Open `.planning/codebase/CONCERNS.md` — if it still cites
> `src/main.zig:1060` / pre-split layout, this plan still applies.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs / dx
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

`.planning/codebase/CONCERNS.md` describes a **pre-modular** `main.zig` (setStr at line 1060, etc.). Agents and humans following it will edit the wrong places. The repo also still has **zero commits**, so prek/`gh` CI never run on a real history. This plan is documentation and checklist only — no product behaviour change.

## Current state

- Live modules: `main`, `model`, `update`, `mole`, `sudo`, `effect_handlers`, `status_json`, `bounded_str` (see `AGENTS.md`).
- Stale: `.planning/codebase/CONCERNS.md` references deleted line numbers in monolithic `main.zig`.
- `plans/001`–`004` DONE; this plan is **008**.
- Git: often `No commits yet on main` with all files untracked.

## Commands you will need

| Purpose | Command | Success |
|---------|---------|---------|
| Sanity | `native test --yes` | exit 0 (must still pass; no code required) |
| Optional commit | `git status` / `git add` / `git commit` | only if operator wants a commit **and** you are allowed to commit |

**Note:** If your agent rules require the user to create commits, **do not commit** — only update docs and leave a checklist in `plans/` or `AGENTS.md`.

## Scope

**In scope:**

- `.planning/codebase/CONCERNS.md` — rewrite or replace with a short “current concerns” pointing at live paths **or** delete if redundant with `plans/README.md` + `AGENTS.md`
- Optional: `.planning/codebase/STACK.md` / `INTEGRATIONS.md` — one-line accuracy fix if they contradict modular layout
- `AGENTS.md` — “First commit” blurb: run `native test`, then commit so CI and prek work
- `plans/README.md` — mark 008 DONE; keep 001–004 as DONE

**Out of scope:**

- Product code under `src/` (unless a comment-only fix)
- Force-push / remote create
- Re-running full architecture audits

## Git workflow

- Branch: `advisor/008-docs-hygiene`
- Prefer **not** creating the first repo commit unless the user explicitly asked for commits in this session
- If committing is allowed and tree is still uncommitted, single commit: `docs: refresh planning map for modular layout`

## Steps

### Step 1: Fix or retire CONCERNS.md

**Preferred:** Replace body with a short current list:

1. Job log may still show ANSI until plan 007 lands (or “done” if 007 already applied).
2. Sudo uses osascript + shell (by design; see rejected list).
3. Fixed-capacity UI strings (`BoundedStr`) — silent truncate by design.
4. External Mole dependency — version not pinned.

Point evidence at **live** files (`src/mole.zig`, `src/sudo.zig`, `src/bounded_str.zig`). Remove obsolete `main.zig:1060` references.

**Alternative:** Delete `.planning/codebase/CONCERNS.md` and add one sentence in `AGENTS.md`: “Do not trust `.planning/` maps without verifying paths.”

**Verify**: `rg "main.zig:1060|setStr" .planning` returns nothing (or file deleted).

### Step 2: First-commit checklist in AGENTS.md

Add a short section:

```markdown
## First commit / CI

1. `native test --yes && native check`
2. `git add` project files (not `.native/` / `zig-out/`)
3. `git commit -m "…"`
4. `prek install` (optional) so hooks run
5. Push to GitHub so `.github/workflows/ci.yml` runs
```

**Verify**: section exists in `AGENTS.md`.

### Step 3: Sanity

```sh
native test --yes
```

Must still pass with zero src changes (or only comment changes).

### Step 4: Update plans index

Set 008 to DONE in `plans/README.md`.

## Test plan

- No new Zig tests required.
- Verification: stale path strings gone; `native test --yes` still green.

## Done criteria

- [ ] No stale pre-split line citations in `.planning/`
- [ ] AGENTS.md has first-commit / CI activation notes
- [ ] `native test --yes` exit 0
- [ ] `plans/README.md` row 008 → DONE

## STOP conditions

- User forbids editing `.planning/` — update only `AGENTS.md` and mark 008 DONE with note.
- Commit required by operator but git identity missing — leave files staged instructions only; do not invent author.

## Maintenance note

After large refactors, either refresh `.planning/` or delete it so it cannot rot again.
