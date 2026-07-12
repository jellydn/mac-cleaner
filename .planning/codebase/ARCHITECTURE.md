# Architecture

**Analysis Date:** 2026-07-12

## Pattern Overview

**Overall:** Elm / The Elm Architecture (TEA) over the Native SDK (Zig 0.16).

**Key Characteristics:**

- Single `Model` holds all UI + system state; `update(model, msg, fx)` mutates state and emits effects (`fx`).
- Effects (`fx.spawn`, `fx.startTimer`, `fx.cancel`) run Mole subprocesses and timers; their completion events feed back as `Msg` variants.
- Declarative UI in `src/app.native` (HTML-like markup) embedded via `@embedFile` (`src/main.zig:49`) and bound to `Model` helper methods; `native_sdk.canvas` builds the widget tree.
- One-way data flow: user event -> `Msg` -> `update` -> effects -> Mole -> JSON -> `Model` -> re-render.
- Logic is split into focused sibling modules (state / update / mole / sudo / json / handlers / strings); `src/main.zig` is a thin wiring layer only.

## Layers

**Model / State:**

- Purpose: Holds all UI + system state (tabs, jobs, sudo phase, parsed status/history, fixed-size buffers).
- Location: `src/model.zig` (canonical `Model` at `src/model.zig:204`).
- Contains: `Model` struct, `Tab`/`JobKind`/`SudoPhase` enums (`src/model.zig:8,24,115`), `ProcessRow`/`HistoryRow`/`LogLine` row structs (`src/model.zig:155,173,194`), view-projection + mutator helpers.
- Depends on: `src/bounded_str.zig` (`BoundedStr(n)`) for all string fields.
- Used by: `src/update.zig`, `src/mole.zig`, `src/sudo.zig`, `src/status_json.zig`, `src/effect_handlers.zig`, `src/main.zig` (re-exported at `src/main.zig:17`).

**Update / Effects:**

- Purpose: Handles every `Msg`, mutates `Model`, emits Mole/timer effects; `boot` seeds initial state.
- Location: `src/update.zig` (`Msg` union at `src/update.zig:13`; `makeUpdate(Effects)` at `src/update.zig:57` returning `boot` at `src/update.zig:59` and `update` at `src/update.zig:79`).
- Contains: `requestJob` (`:138`), `ensureSudoThenStartJob` (`:147`), `onSudoAuthDone` (`:162`); status/history/job exits delegate to `src/effect_handlers.zig` (`src/update.zig:107,108,110`).
- Depends on: `src/model.zig`, `src/mole.zig`, `src/sudo.zig`, `src/status_json.zig`, `src/effect_handlers.zig`, `native_sdk` effects.
- Used by: `src/main.zig` wires `Loop = update_mod.makeUpdate(Effects)` at `src/main.zig:46`.

**Mole Spawning (Effects source):**

- Purpose: Resolve the Mole binary and spawn status/history/job subprocesses.
- Location: `src/mole.zig` (`resolveMole` at `src/mole.zig:48`; `spawnStatus`/`spawnHistory`/`spawnJob`/`cancelJob` at `src/mole.zig:85,99,113,142`; `applyMoleMissing`/`markMoleAvailable` at `src/mole.zig:70,80`).
- Effect keys (namespaced u64): `status_key=1`, `history_key=2`, `job_key=3` (`src/mole.zig:18-20`).

**Sudo (Effects source):**

- Purpose: One-shot local admin grant + keepalive so Mole can clean system caches.
- Location: `src/sudo.zig` (`spawnAuth` at `src/sudo.zig:41`; `spawnPing` at `src/sudo.zig:31`; `ensureThen` at `src/sudo.zig:106`; `handleAuthDone`/`handlePingDone` at `src/sudo.zig:71,96`; scripts embedded at `src/sudo.zig:12-13`).
- Effect keys: `auth_key=4`, `ping_key=5`, `keepalive_timer_key=2` (`src/sudo.zig:8-10`).

**View / Markup:**

- Purpose: Declarative UI bound to `Model` via `{helper}` expressions and `on-press="msg"` handlers.
- Location: `src/app.native` (embedded at `src/main.zig:49` via `@embedFile("app.native")`, watched at `src/app.native` for hot reload, `src/main.zig:74`).
- Depends on: `Model` helper methods (e.g. `statusBar`, `actionsDisabled`, `sudoStatusText`, `confirmTitle`).
- Used by: `native_sdk.canvas.MarkupView(Model, Msg).build` (`src/tests.zig:20`).

**Engine (Native SDK):**

- Purpose: Owns the render/event loop, GPU canvas, and subprocess + timer effects.
- Location: external `native_sdk` (`@import("native_sdk")`), wired via `runner.runWithOptions` at `src/main.zig:67`.
- Contains: `UiApp(Model, Msg)`, `Effects` (`fx.spawn`/`fx.startTimer`/`fx.cancel`), `canvas` widget tree.

## Data Flow

**Initial boot:**

1. `main` (`src/main.zig:67`) creates `CleanerApp` and runs `runner`; `initialModel` (`src/main.zig:51`) resolves the Mole path into `Model`.
2. `boot` (`src/update.zig:59`) resolves Mole (`src/mole.zig:48`), spawns `status` + `history` (`src/mole.zig:85,99`), probes sudo (`src/sudo.zig:41`), and starts a 45s repeating `refresh_timer_key=1` (`src/update.zig:71-76`).
3. Mole `--json` output is collected; `applyStatusJson` (`src/status_json.zig:9`) / `applyHistoryJson` (`src/status_json.zig:99`) parse into `Model`; markup re-renders. Disk stats prefer the internal root mount `/` via `pickRootDisk` (`src/status_json.zig:135`).

**User action -> job:**

1. Markup `on-press` emits a `Msg` (e.g. `start_clean_run`), dispatched by `update` (`src/update.zig:79`).
2. `requestJob` -> `ensureSudoThenStartJob` (`src/update.zig:138,147`); `mole.spawnJob` (`src/mole.zig:113`) builds argv from `JobKind.fillArgv` (`src/model.zig:81`) -> `mole clean|optimize|purge [--dry-run]`.
3. `job_line`/`job_done` append to the log (`Model.appendLog`, `src/model.zig:472`); on success, status + history are refreshed (`src/update.zig:110`).

**Safety gating:**

- Real `clean_run` / `optimize_run` / `purge_run` require `JobKind.needsConfirm` (`src/model.zig:45`) -> `confirm_job` dialog (`confirm_pending_job`) before spawning.
- Dry-runs (`*_dry`) are preview-only and never delete.
- Sudo is one-shot: `SudoPhase` (`src/model.zig:115`) drives grant (`unknown -> inactive|prompting -> active`) and a 30s keepalive (`src/sudo.zig:15`).

**State Management:**

- Per-frame `Model` mutated by `update`; markup binds read-only helper methods. Arrays are fixed-size buffers and silently truncated: `[8]ProcessRow` (`src/model.zig:266`), `[12]HistoryRow` (`src/model.zig:282`), `[48]LogLine` (`src/model.zig:273`).

## Key Abstractions

- **JobKind:** Enum of job modes (`clean_dry/clean_run/optimize_dry/optimize_run/purge_dry/purge_run`) with policy methods `needsConfirm`/`wantsSudo`/`refreshesAfter`/`subcommand`/`isDryRun`/`fillArgv` (`src/model.zig:24`).
- **SudoPhase:** State-machine for the one-shot admin grant (`unknown/inactive/prompting/active`) (`src/model.zig:115`).
- **BoundedStr(n):** Generic fixed-capacity string for markup-safe storage (`src/bounded_str.zig:5`); `set` silently truncates.
- **Effects / Msg:** `Msg` union (`src/update.zig:13`) carries user intents and effect-completion payloads (`status_done`, `history_done`, `job_line`, `job_done`, `sudo_auth_done`, `sudo_ping_done`, `refresh_tick`, `sudo_keepalive_tick`). Effects are `fx.spawn`/`fx.startTimer`/`fx.cancel` supplied by `native_sdk` (`CleanerApp.Effects`, `src/main.zig:45`).

## Entry Points

- **main(init):** `src/main.zig:67`. Builds `CleanerApp`, sets `initialModel`, `runner.runWithOptions` with window + security config.
- **initialModel():** `src/main.zig:51`. Resolves Mole path into a fresh `Model`.
- **boot(model, fx):** `src/update.zig:59`. Seeds first status/history + sudo probe + 45s timer (invoked by `init_fx` at `src/main.zig`).

## Error Handling

**Strategy:** Mole/subprocess failures are surfaced into `Model` flags (no exceptions); JSON parse failures set `status_error`/`history_error`.

**Patterns:**

- Spawn `rejected` / `spawn_failed` -> `health_msg = "Could not run mole — is it installed?"` (`src/effect_handlers.zig:28`).
- Non-zero exit -> error text taken from `stderr_tail` (`src/effect_handlers.zig:21`).
- JSON parse error -> `status_error = true` (`src/effect_handlers.zig:16`).
- Sudo grant cancelled/failed handled in `src/sudo.zig:71` (`handleAuthDone`), falling back to user-level Mole.

## Cross-Cutting Concerns

**Logging:** Job output streamed via `job_line` -> `Model.appendLog` (`src/model.zig:472`); bounded to 48 lines, oldest dropped; ANSI stripped via `stripAnsi` (`src/model.zig:494`).

**Validation:** `native check` validates `src/app.native` + `app.zon`; markup build prints `app.native:<line>:<col>: <msg>` (`src/tests.zig:25`). Tests assert literal UI strings from `src/app.native` (`src/tests.zig` `"Open Clean"`, `"Clean · dry-run"`, `"Grant admin once"`).

**Authentication:** One-shot sudo grant via `osascript` dialog (`src/scripts/grant-sudo.sh`, embedded `src/sudo.zig:12`), keepalive every 30s (`sudo -n -v`, `src/sudo.zig:15,31`); silent boot probe (`src/scripts/probe-sudo.sh`).

---

_Architecture analysis: 2026-07-12_
