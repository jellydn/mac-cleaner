# Plan 001: Extract and characterization-test effect handlers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: There may be **no git commits**. Compare the
> "Current state" excerpts below to the live files. If `onStatusDone` /
> `onHistoryDone` / `onJobDone` no longer exist in `src/update.zig` or their
> bodies differ materially, STOP and report.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

Status/history/job failure paths in `update` set UI-facing model fields (`status_error`, `health_msg`, `job_summary`, log lines) but have **zero unit tests**. Today only JSON success parsing, JobKind policy, and markup presence are tested. The next person who refactors sudo or error UX has no safety net. This plan extracts pure handlers and adds characterization tests so later plans (and accidental regressions) are caught by `native test`.

## Current state

- `src/update.zig` — TEA `Msg` + `makeUpdate(Effects)`; private handlers:
  - `onStatusDone` (~lines 151–175)
  - `onHistoryDone` (~lines 177–192)
  - `onJobDone` (~lines 194–226)
- `src/tests.zig` — pattern for pure model tests (see `test "sudo ensureThen phases"`).
- `src/model.zig` — `Model` with `status_error`, `history_error`, `health_msg`, `job_summary`, `appendLog`, `setJobSummary`.
- `native_sdk.EffectExit` has fields: `key`, `code`, `reason` (`.exited` / `.signaled` / `.cancelled` / `.rejected` / `.spawn_failed`), `output`, `stderr_tail`.

### Excerpt: status failure handling today (`src/update.zig`)

```zig
fn onStatusDone(model: *Model, exit: native_sdk.EffectExit) void {
    model.status_loading = false;
    switch (exit.reason) {
        .exited => {
            if (exit.code == 0) {
                status_json.applyStatusJson(model, exit.output) catch {
                    model.status_error = true;
                    model.health_msg.set("Failed to parse status JSON");
                };
            } else {
                model.status_error = true;
                if (exit.stderr_tail.len > 0) {
                    model.health_msg.set(exit.stderr_tail);
                } else {
                    model.health_msg.set("mole status failed");
                }
            }
        },
        .rejected, .spawn_failed => {
            model.status_error = true;
            model.health_msg.set("Could not run mole — is it installed?");
        },
        .cancelled, .signaled => {},
    }
}
```

### Conventions to match

- Zig 0.16, modules under `src/` imported via `@import("…")`.
- Tests live in `src/tests.zig` or colocated `test` blocks; suite runs via root `test { _ = @import("tests.zig"); }` in `main.zig`.
- Prefer pure functions with no `Effects` dependency for characterization tests (do **not** require the full UiApp fake executor unless you already know it well).
- `AGENTS.md`: keep modules split; do not re-merge into a god `main.zig`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests | `native test --yes` | exit 0; all tests pass (count will rise) |
| Markup | `native check` | `src/app.native: ok` |
| Build | `native build --yes` | exit 0 |

## Scope

**In scope:**

- `src/effect_handlers.zig` (create) — pure handlers for status/history/job exits
- `src/update.zig` — call the extracted handlers from `onStatusDone` / `onHistoryDone` / `onJobDone`
- `src/tests.zig` — characterization tests for those handlers
- `src/main.zig` — only if you need `test { _ = @import("effect_handlers.zig"); }` (optional if tests.zig imports it)
- `AGENTS.md` — one-line mention of `effect_handlers.zig` if you touch the module table

**Out of scope:**

- Changing sudo grant / keepalive behavior
- Fake-executor UiApp integration tests (optional stretch; not required)
- UI copy or `app.native`
- Plan 002–004 features

## Git workflow

- Branch (if committing): `advisor/001-effect-handler-tests`
- Commit message style: short imperative, e.g. `test: characterize status/history/job effect handlers`
- Do not push/PR unless asked

## Steps

### Step 1: Create `src/effect_handlers.zig` with pure handlers

Move the **behavior** of `onStatusDone`, `onHistoryDone`, and the model-mutation part of `onJobDone` into public functions that take `*Model` and `native_sdk.EffectExit` (and for job done, optionally `*Effects` only if you must spawn refreshes — **prefer** splitting):

1. `pub fn applyStatusExit(model: *Model, exit: native_sdk.EffectExit) void`  
   - Same logic as current `onStatusDone` (including `status_loading = false` and JSON apply).
2. `pub fn applyHistoryExit(model: *Model, exit: native_sdk.EffectExit) void`  
   - Same as current `onHistoryDone`.
3. `pub fn applyJobExit(model: *Model, exit: native_sdk.EffectExit) void`  
   - Sets `job_running = false`, summary/log for success/failure/cancel/spawn_failed/signaled.  
   - **Do not** call `mole.spawnStatus` here. Instead return a `bool` (or enum) `should_refresh` when `exit.reason == .exited` and `model.job.refreshesAfter()` after handling (even on non-zero exit, match **current** behavior: refresh only when `refreshesAfter()` and reason is `.exited` — read the live `onJobDone` carefully and characterize **exactly** what it does today).

Read live `onJobDone` before coding. Today it refreshes when `model.job.refreshesAfter()` inside the `.exited` branch only (both success and non-zero exit codes). Preserve that.

**Verify**: file exists; `native test --yes` still passes (if not wired yet, import only from tests later).

### Step 2: Wire `update.zig` to call the pure handlers

- `onStatusDone` → `effect_handlers.applyStatusExit`
- `onHistoryDone` → `effect_handlers.applyHistoryExit`
- `onJobDone` → apply job exit; if refresh needed, keep `mole.spawnStatus` / `spawnHistory` in `update.zig` only

**Verify**: `native test --yes` → all existing tests still pass.

### Step 3: Add characterization tests in `src/tests.zig`

Add tests that construct a minimal `native_sdk.EffectExit` and call the pure handlers. Pattern after existing pure tests in `src/tests.zig` (`sudo ensureThen phases`).

**Required cases:**

| # | Case | Expect |
|---|------|--------|
| 1 | status `spawn_failed` | `status_loading == false`, `status_error == true`, health_msg contains "Could not run mole" |
| 2 | status exited non-zero, empty stderr | health_msg is `"mole status failed"` |
| 3 | status exited non-zero, stderr_tail set | health_msg equals stderr_tail (or prefix if BoundedStr truncates) |
| 4 | status exited 0 with invalid JSON body `"{not json"` | `status_error == true`, parse failure message |
| 5 | history `rejected` | `history_loading == false`, `history_error == true` |
| 6 | job exited 0 | `job_running == false`, summary success, log contains `"Done"` |
| 7 | job cancelled | summary/log cancelled |
| 8 | job spawn_failed | summary/log about could not start mole |
| 9 | job exited 0 with `model.job = .clean_run` | `applyJobExit` returns/signals refresh true; with `.clean_dry` signals false |

For EffectExit construction, set at least:

```zig
var exit: native_sdk.EffectExit = .{
    .key = 1,
    .reason = .spawn_failed,
    .code = -1,
};
// or .exited with .code = 1, .stderr_tail = "boom" if the field is assignable
```

If `stderr_tail` / `output` are not free-form assignable in tests (slice lifetime), check the struct in the installed SDK and use string literals that live for the test.

**Verify**: `native test --yes` → all pass; new tests appear in the tally (expect ≥ 11 + your new cases).

### Step 4: Final gates

**Verify**:

```sh
native test --yes
native check
native build --yes
```

All exit 0.

## Test plan

- New tests listed in Step 3, in `src/tests.zig`.
- Structural pattern: `test "sudo ensureThen phases"` and `test "parses mole status json into the model"`.
- Do not assert on `app.native` button labels in this plan.

## Done criteria

- [ ] `src/effect_handlers.zig` exists with public apply* functions
- [ ] `src/update.zig` delegates status/history/job exit handling to them
- [ ] Characterization tests cover spawn_failed, non-zero exit, bad JSON, job cancel/fail/success, refresh signal
- [ ] `native test --yes` exit 0
- [ ] `native check` exit 0
- [ ] `native build --yes` exit 0
- [ ] `plans/README.md` status for 001 set to `DONE`

## STOP conditions

- `EffectExit` fields cannot be constructed in unit tests without private APIs → STOP and report the SDK type definition; do not invent a parallel fake struct that drifts from production.
- Extracting handlers requires large `UiApp` / fake-executor setup beyond pure functions → STOP; prefer pure extract only.
- Existing tests fail after wiring for reasons unrelated to this extract → STOP and report the failure log.

## Maintenance note

Future changes to error strings (`"Could not run mole — is it installed?"`, `"mole status failed"`, `"Done"`) must update the characterization tests. When adding new effect kinds, add a pure handler + tests in the same PR.
