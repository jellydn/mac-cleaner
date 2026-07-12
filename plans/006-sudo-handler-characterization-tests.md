# Plan 006: Characterization tests for sudo auth/ping handlers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Compare `src/sudo.zig` and sudo-related tests in `src/tests.zig`
> to the excerpts below. Plan 001 covered effect_handlers; this covers **sudo**.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none (optional after 005)
- **Category**: tests
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

Admin grant is the highest-risk control surface in the app. `ensureThen` is tested; **`handleAuthDone` and `handlePingDone` are not**. Regressions in “grant then start pending job”, cancel (exit 2), or session expiry leave silent wrong phase with no test failure.

## Current state

### `src/sudo.zig` (handlers)

- `handleAuthDone(Effects, model, fx, exit_code, reason_ok, was_interactive, on_keepalive) JobKind`
  - On success: `markActive` (phase `.active` + keepalive timer once)
  - On failure: phase `.inactive`
  - Returns and clears `pending_after_sudo`
- `handlePingDone(model, ok)`
  - ok → `.active`; fail while active → `.inactive` + log line
- `ensureThen` already tested in `src/tests.zig` (`test "sudo ensureThen phases"`)

### Wiring (`src/update.zig` `onSudoAuthDone`)

```zig
const interactive = wasInteractiveAuth(model); // phase == .prompting
const reason_ok = exit.reason == .exited;
const code: ?i32 = if (reason_ok) exit.code else null;
const pending = sudo.handleAuthDone(..., code, reason_ok, interactive, Effects.timerMsg(.sudo_keepalive_tick));
// then spawn job if pending != .none
```

### Conventions

- Prefer **pure** tests that call `handleAuthDone` / `handlePingDone` without full UiApp.
- `handleAuthDone` is generic over `Effects` and needs `fx` + `on_keepalive` for `startKeepalive`. For unit tests without Effects:
  - **Option A (preferred):** split pure phase transition from timer start:
    - `pub fn applyAuthResult(model: *Model, granted: bool, was_interactive: bool) JobKind` sets phase + returns pending, clears pending.
    - `markActive` / keepalive only called from update when granted.
  - **Option B:** pass a minimal stub Effects if the SDK allows — only if A is harder.
- Prefer **Option A** so tests stay dependency-light. Keep current public API working for update.zig (thin wrapper).

## Commands you will need

| Purpose | Command | Success |
|---------|---------|---------|
| Tests | `native test --yes` | exit 0; new tests in tally |
| Check | `native check` | exit 0 |
| Build | `native build --yes` | exit 0 |

## Scope

**In scope:**

- `src/sudo.zig` — optional pure extract `applyAuthResult` / keep `handlePingDone` as-is
- `src/update.zig` — only if wiring must call new pure function then startKeepalive
- `src/tests.zig` — new cases
- Do **not** change grant shell script

**Out of scope:**

- Authorization Services rewrite
- UI changes for sudo card
- Plan 005 mole_available

## Git workflow

- Branch: `advisor/006-sudo-handler-tests`
- Commit example: `test: characterize sudo auth and ping handlers`

## Steps

### Step 1: Extract pure auth result application (if needed)

Introduce something like:

```zig
/// Clears pending_after_sudo, sets phase, returns previous pending job.
pub fn applyAuthResult(model: *Model, granted: bool) JobKind {
    const pending = model.pending_after_sudo;
    model.pending_after_sudo = .none;
    model.sudo_phase = if (granted) .active else .inactive;
    return pending;
}
```

Then `handleAuthDone` becomes: compute `granted`, call `applyAuthResult`, if granted call `markActive` (which sets active again + keepalive — avoid double-setting: either `applyAuthResult` only sets inactive on fail and `markActive` on success, or `applyAuthResult` sets phase and `startKeepalive` is separate).

**Clean split:**

```zig
pub fn takePendingJob(model: *Model) JobKind { ... }

pub fn applyAuthOutcome(model: *Model, granted: bool) void {
    model.sudo_phase = if (granted) .active else .inactive;
}
```

`handleAuthDone`: take pending; if granted markActive else apply inactive; return pending.

**Verify**: existing tests still pass.

### Step 2: Characterization tests

Add tests in `src/tests.zig` calling pure functions (or `handlePingDone` which needs no Effects):

| # | Case | Expect |
|---|------|--------|
| 1 | pending `.clean_dry`, grant success | pending returned `.clean_dry`, phase `.active` after mark/apply |
| 2 | pending none, grant fail | phase `.inactive`, returned `.none` |
| 3 | `handlePingDone(true)` from inactive | phase `.active` |
| 4 | `handlePingDone(false)` from active | phase `.inactive`, log mentions expired/grant |
| 5 | `ensureThen` still grant_first when inactive (regression) | existing test still green |

If `handleAuthDone` still requires Effects, only test pure pieces + `handlePingDone`.

**Verify**: `native test --yes` — count increases; all pass.

### Step 3: Optional — pending job integration without Effects

Document in test comments that update.zig spawns job when pending != none; pure test proves pending is returned correctly so wiring can stay thin.

### Step 4: Final gates

```sh
native test --yes && native check && native build --yes
```

## Test plan

- New tests listed above in `src/tests.zig`
- Pattern: `test "sudo ensureThen phases"` and effect_handlers tests

## Done criteria

- [ ] Pure sudo outcome logic is unit-tested (grant success/fail + ping expire)
- [ ] Pending job is returned/cleared correctly under test
- [ ] `native test --yes` exit 0
- [ ] `native check` / `native build --yes` exit 0
- [ ] `plans/README.md` row 006 → DONE

## STOP conditions

- Cannot unit-test without instantiating full UiApp Effects → extract pure phase functions (Step 1); do not skip tests.
- Changing handleAuthDone breaks keepalive → keep markActive path identical; only test pure pending/phase bits.

## Maintenance note

Any new SudoPhase value must update these tests. Keep sudo tests free of osascript/network.
