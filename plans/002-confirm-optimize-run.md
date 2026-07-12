# Plan 002: Require confirmation before `optimize_run`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Compare excerpts below to live `src/model.zig` and `src/app.native`.
> If `needsConfirm` already includes `.optimize_run`, mark this plan DONE after
> confirming tests assert it, and skip code changes.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (prefer after 001 if both run, but not required)
- **Category**: bug (safety UX)
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

Destructive (or system-mutating) Mole actions should not run on a single mis-click. **Clean · run** and **Purge · run** already open an in-app confirm card. **Optimize · run** does not — it goes straight to sudo/job pipeline. Optimize refreshes caches/services and can change machine behavior; it should use the same confirm gate.

## Current state

### `JobKind.needsConfirm` (`src/model.zig`)

```zig
pub fn needsConfirm(self: JobKind) bool {
    return self == .clean_run or self == .purge_run;
}
```

### Confirm copy (`src/model.zig` — `confirmTitle` / `confirmBody`)

Today only `.clean_run` and `.purge_run` have specific strings; `else => "Confirm"` / `"Continue?"`.

### Pipeline (`src/update.zig`)

```zig
fn requestJob(model: *Model, fx: *Effects, kind: JobKind) void {
    if (model.job_running or model.sudo_phase.isPrompting()) return;
    if (kind.needsConfirm()) {
        model.confirm_job = kind;
        return;
    }
    ensureSudoThenStartJob(model, fx, kind);
}
```

### UI (`src/app.native`)

Confirm card already binds `{confirmTitle}` / `{confirmBody}` and `confirm_pending_job`. No markup change is **required** if model copy is updated — but add optimize copy so the dialog is not the generic fallback.

### Test that must flip (`src/tests.zig`)

```zig
try testing.expect(!JobKind.optimize_run.needsConfirm());
```

This assertion is **currently correct for the bug** and must become `try testing.expect(JobKind.optimize_run.needsConfirm());`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests | `native test --yes` | exit 0 |
| Markup | `native check` | exit 0 |
| Build | `native build --yes` | exit 0 |

## Scope

**In scope:**

- `src/model.zig` — `needsConfirm`, `confirmTitle`, `confirmBody`
- `src/tests.zig` — policy test expectation for `optimize_run`
- Optional: `src/app.native` only if you want a static note near Optimize · run (not required)

**Out of scope:**

- Changing sudo grant behavior
- Making dry-run require confirm
- Adding confirm for other actions
- CI (plan 004)

## Git workflow

- Branch: `advisor/002-confirm-optimize-run`
- Commit message example: `fix: require confirm before optimize run`

## Steps

### Step 1: Update `needsConfirm`

In `src/model.zig`:

```zig
pub fn needsConfirm(self: JobKind) bool {
    return self == .clean_run or self == .optimize_run or self == .purge_run;
}
```

**Verify**: `rg "needsConfirm" src/model.zig` shows optimize_run included.

### Step 2: Add confirm copy for optimize

In `confirmTitle`:

```zig
.optimize_run => "Confirm real optimize",
```

In `confirmBody` (keep tone consistent with clean/purge — prefer dry-run first):

```zig
.optimize_run => "This runs mole optimize and may refresh system caches and services. Prefer dry-run first. Continue?",
```

Keep `.clean_run` and `.purge_run` strings unchanged.

**Verify**: strings present via `rg "Confirm real optimize" src/model.zig`.

### Step 3: Fix and extend tests

In `src/tests.zig` test `"JobKind policy: confirm, sudo, refresh, argv"`:

- Change to: `try testing.expect(JobKind.optimize_run.needsConfirm());`
- Keep dry-run cases false: `clean_dry`, and add `optimize_dry` if not already covered: `try testing.expect(!JobKind.optimize_dry.needsConfirm());`

Optional small UI test: with `model.tab = .clean` and `model.confirm_job = .optimize_run`, build tree and expect text `"Confirm real optimize"` (if markup uses confirmTitle when showConfirm). Only if `showConfirm` is true when `confirm_job != .none` (it is).

**Verify**: `native test --yes` → all pass.

### Step 4: Final gates

```sh
native test --yes && native check && native build --yes
```

## Test plan

- Update existing JobKind policy test (required).
- Optional: clean-tab tree test with `confirm_job = .optimize_run` finds heading text.
- Pattern: existing `test "JobKind policy: confirm, sudo, refresh, argv"`.

## Done criteria

- [ ] `JobKind.optimize_run.needsConfirm()` is true
- [ ] `JobKind.optimize_dry.needsConfirm()` is false
- [ ] Confirm title/body for optimize_run are specific (not generic "Confirm")
- [ ] `native test --yes` exit 0
- [ ] `native check` exit 0
- [ ] `native build --yes` exit 0
- [ ] `plans/README.md` row 002 → `DONE`

## STOP conditions

- Product owner (user) explicitly rejects confirm for optimize → STOP; do not force the change; report and leave plan BLOCKED.
- Confirm dialog does not appear for optimize after code change because markup only shows confirm for certain jobs — inspect `showConfirm` / `confirm_job` bindings; if broken, fix binding, do not remove the needsConfirm change.

## Maintenance note

Any new **mutating** JobKind (e.g. future installer run) should extend `needsConfirm` and confirm copy in the same PR.
