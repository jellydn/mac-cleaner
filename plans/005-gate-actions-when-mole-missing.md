# Plan 005: Gate actions when Mole is missing + show Overview status error

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Compare excerpts below to live `src/model.zig`, `src/mole.zig`,
> `src/update.zig`, `src/app.native`. Plans 001–004 are DONE; do not re-do them.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (builds on plan 003’s `applyMoleMissing`)
- **Category**: bug / UX
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

Plan 003 surfaces “Mole not found” in `health_msg` / `status_error`, but **Clean/Optimize/Purge and Refresh still work**. Jobs spawn with argv0 `"(not found)"` and fail messily. History already shows a dedicated error banner; Overview does not. This plan disables actions when Mole is unusable and mirrors History’s error banner on Overview.

## Current state

### `actionsDisabled` (`src/model.zig`)

```zig
pub fn actionsDisabled(self: *const Model) bool {
    return self.job_running or self.sudo_phase.isPrompting();
}
```

Does **not** consider `status_error` or a “mole found” flag.

### Missing mole (`src/mole.zig`)

```zig
pub fn applyMoleMissing(model: *Model) void {
    model.setMolePath("(not found)");
    model.status_loading = false;
    model.status_error = true;
    model.history_loading = false;
    model.history_error = true;
    model.health_msg.set("Mole not found — brew install mole (or put mole on PATH)");
}
```

### Spawn still always tries (`src/mole.zig` spawnStatus/spawnJob)

Uses `model.molePath()` without checking found.

### Overview header Refresh (`src/app.native`)

```xml
<button size="sm" variant="ghost" on-press="refresh_status" disabled="{job_running}">Refresh</button>
```

Uses `job_running` only, not `actionsDisabled`.

### History has error banner; Overview does not (`src/app.native`)

```xml
<if test="{history_error}">
  <text foreground="destructive">Could not load history. Is Mole installed?</text>
</if>
```

`status_error` is in `Model.view_unbound` and never bound in markup.

### Conventions

- Prefer reusing `status_error` **or** add an explicit `mole_found: bool = true` set false only by `applyMoleMissing` and true when resolve succeeds. Explicit flag is clearer than overloading `status_error` (which also means parse failures).
- Recommended: add `mole_available: bool = true` (or `mole_found`). Set `false` in `applyMoleMissing`; set `true` when `resolveMole` succeeds in boot/`initialModel`.
- `actionsDisabled` should include `!mole_available`.
- Guard `spawnStatus` / `spawnHistory` / `spawnJob` / refresh handlers: no-op if `!mole_available`.
- Markup: bind Overview error using `status_error` **or** a helper `showStatusError` that is true when `status_error` or `!mole_available`. Prefer showing `healthMsg` in destructive colour when error.

## Commands you will need

| Purpose | Command | Success |
|---------|---------|---------|
| Tests | `native test --yes` | exit 0 |
| Check | `native check` | exit 0 |
| Build | `native build --yes` | exit 0 |

## Scope

**In scope:**

- `src/model.zig` — flag + `actionsDisabled` + optional view helpers
- `src/mole.zig` — `applyMoleMissing` sets flag; spawn guards
- `src/main.zig` / `src/update.zig` — set flag true on successful resolve; refresh no-op
- `src/app.native` — Overview error banner; Refresh uses `actionsDisabled` or new bind
- `src/tests.zig` — actionsDisabled when missing; spawn path not required if pure guard tested
- `AGENTS.md` — one line if module table needs it

**Out of scope:**

- PATH discovery changes (003 done)
- Sudo grant changes
- ANSI stripping (plan 007)
- CI changes

## Git workflow

- Branch: `advisor/005-gate-mole-missing`
- Commit example: `fix: disable actions when mole is missing`

## Steps

### Step 1: Add `mole_available` (or equivalent) on Model

```zig
mole_available: bool = true,
```

Add to `view_unbound` if not bound directly (or bind via helper).

In `applyMoleMissing`:

```zig
model.mole_available = false;
// keep existing fields
```

Where resolve succeeds (`boot`, `initialModel`):

```zig
model.mole_available = true;
model.setMolePath(resolved.path);
```

**Verify**: `rg mole_available src/`

### Step 2: Extend `actionsDisabled`

```zig
pub fn actionsDisabled(self: *const Model) bool {
    return !self.mole_available or self.job_running or self.sudo_phase.isPrompting();
}
```

Optional helper:

```zig
pub fn showStatusError(self: *const Model) bool {
    return self.status_error or !self.mole_available;
}
```

**Verify**: unit test: after `applyMoleMissing`, `actionsDisabled() == true` even if not job_running.

### Step 3: Guard spawns

At top of `spawnStatus`, `spawnHistory`, `spawnJob`:

```zig
if (!model.mole_available) return;
```

For `spawnStatus`/`spawnHistory`, if already loading, existing early returns stay.

Also: `refresh_status` / `refresh_history` / `refresh_tick` paths should not set loading true if they call spawn that no-ops — because spawn returns before setting loading, OK.

**Verify**: `native test --yes`

### Step 4: Overview + Refresh markup

1. Change Refresh `disabled="{job_running}"` → `disabled="{actionsDisabled}"` (or a bind that includes mole missing + job).
2. After health card (or top of Overview scroll), add:

```xml
<if test="{showStatusError}">
  <text foreground="destructive" wrap="true">{healthMsg}</text>
</if>
```

(or `status_error` if you only show parse/spawn errors and always set status_error when !mole_available — already true in applyMoleMissing).

If using `status_error` directly, remove it from `view_unbound` and bind `status_error` / keep helper for clarity.

**Verify**: `native check` → ok; tree test optional for destructive text after applyMoleMissing + buildTree.

### Step 5: Tests

In `src/tests.zig`:

1. After `mole.applyMoleMissing(&model)`, expect `actionsDisabled() == true`.
2. With `mole_available = true`, job not running, sudo inactive → `actionsDisabled() == false`.
3. Existing `applyMoleMissing` test: also assert `!mole_available` if field public/readable.

**Verify**: `native test --yes`

### Step 6: Final gates

```sh
native test --yes && native check && native build --yes
```

## Test plan

- Extend `applyMoleMissing` / `actionsDisabled` tests in `src/tests.zig`.
- Pattern: `test "actionsDisabled follows job and sudo prompting"`.

## Done criteria

- [ ] When mole missing, Clean/Optimize/Purge/Grant/Refresh are disabled
- [ ] Spawns no-op when `!mole_available`
- [ ] Overview shows a clear error using health message / status_error
- [ ] `native test --yes` exit 0
- [ ] `native check` exit 0
- [ ] `native build --yes` exit 0
- [ ] `plans/README.md` row 005 → DONE

## STOP conditions

- Markup rejects binding `status_error` bool — use a `showStatusError` method returning bool instead.
- Disabling Refresh when status_error after a **temporary** parse failure is wrong product-wise — then gate **only** on `!mole_available`, not all `status_error`. Prefer that: **only disable on `!mole_available`**, keep Refresh enabled after a one-off parse failure.

## Maintenance note

If Mole can be “installed” at runtime without restart, add a “Retry discover” button that re-runs resolve and clears `mole_available`. Not in this plan.
