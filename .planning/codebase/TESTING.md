# Testing Patterns

**Analysis Date:** 2026-07-12

## Test Framework

**Runner:** `native test` — the project's wrapper over `zig test` that runs the `std.testing` suite. No third-party test lib.

**Assertion Library:** `std.testing` (`expectEqual`, `expectEqualStrings`, `expect`).

**Run Commands:**

```bash
native test          # run the whole suite (headless UI + JSON parse + layout + unit)
just test            # same, via Justfile
```

No watch mode, no filter flag, no coverage step.

## Test File Organization

**Location:** primary suite in `src/tests.zig`; module-level unit tests live next to the code:

- `src/bounded_str.zig` (`BoundedStr.set`/`slice` round-trip).
- `src/status_json.zig` (`pickRootDisk` prefers internal root).
- `src/mole.zig` (`joinPath`).
- `src/effect_handlers.zig`, `src/sudo.zig`, `src/model.zig` are exercised from `src/tests.zig` via pure calls (no subprocess).

**Naming:** `test "descriptive name" { ... }` (Zig convention).

**Structure:** a `test` block at the bottom of `src/main.zig` pulls in the test modules (`_ = @import("tests.zig")` etc.), so `native test` compiles and runs them all.

## Test Structure

**JSON/parsing tests:** build a `Model` via `main.initialModel()` (`src/tests.zig:56`), call `status_json.applyStatusJson`/`applyHistoryJson` with an inline sample JSON string, then assert on resulting `Model` fields (e.g. the status test asserts `health_score`, `hardwareText`, `disk_pct`, `trash_gb`, `top_process_count`).

**UI/markup tests:** build the widget tree with `buildTree(arena, &model)` (`src/tests.zig:20`), which calls `AppMarkup.init(arena, main.app_markup).build(...)`. Assert with `expectByText`/`findAnyText` (`src/tests.zig:40,47`). Per-test allocation uses `std.heap.ArenaAllocator` (deferred `deinit`).

**Policy / unit tests:** `JobKind` policy (`needsConfirm`/`wantsSudo`/`refreshesAfter`/`subcommand`/`fillArgv`, `src/tests.zig:175`), `sudo.ensureThen` phases (`src/tests.zig:390`), `effect_handlers` exit mutations (`:202`), `stripAnsi` (`:375`), `actionsDisabled` (`:327`), `applyMoleMissing` (`:302`).

## Mocking

**Framework:** none. **Fixtures:** none (inline JSON strings only).

Mole is never invoked in tests; subprocess output is simulated by feeding inline JSON/strings to pure handlers (`effect_handlers`, `status_json`). `Effects` is abstracted at the call site (`makeUpdate(comptime Effects: type)`), so pure handlers test without spawning.

## Gotchas

- **Tests assert LITERAL UI strings from `src/app.native`** ("Mac Cleaner", "Overview", "Clean", "History", "Open Clean", "Clean · dry-run", "Clean · run", "Optimize · dry-run", "Purge · dry-run", "Purge · run", "Grant admin once"). Renaming a button/tab in `app.native` breaks the test — the helpers print "if you changed app.native, update this test to match" (`src/tests.zig:42`).
- A **malformed `src/app.native`** fails the markup-build test with a precise `app.native:<line>:<col>: <message>` diagnostic (`src/tests.zig:25`).
- `native test` also runs in the pre-commit hook (`.pre-commit-config.yaml`), so string/JSON drift fails commits before they land.
- **Coverage is not measured or enforced.**

## Test Types

**Unit:** pure handlers (`effect_handlers`, `status_json.pickRootDisk`, `bounded_str`, `mole.joinPath`, `sudo` phase transitions, `stripAnsi`) — no subprocess.

**Integration:** markup build + canvas layout (`src/tests.zig:126`, `:163`) exercising the real `app.native` against a `Model`.

**E2E:** not used.

---

_Testing analysis: 2026-07-12_
