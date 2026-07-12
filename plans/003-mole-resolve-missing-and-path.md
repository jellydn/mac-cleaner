# Plan 003: Resolve Mole via PATH and fail clearly when missing

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Compare `src/mole.zig` `resolveMole` and boot in `src/update.zig`
> to the excerpts below.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt / correctness
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

`resolveMole()` only checks four Homebrew paths and **always returns a string**, even when no binary exists. Users with Mole only on `$PATH` (or not installed) get a delayed `"Could not run mole — is it installed?"` after a failed spawn instead of a clear boot-time state. This plan makes discovery correct and surfaces missing Mole immediately in the model/UI path already used for status errors (`health_msg` / `status_error`).

## Current state

### `src/mole.zig`

```zig
const mole_candidates = [_][]const u8{
    "/opt/homebrew/bin/mole",
    "/usr/local/bin/mole",
    "/opt/homebrew/bin/mo",
    "/usr/local/bin/mo",
};

pub fn resolveMole() []const u8 {
    for (mole_candidates) |path| {
        if (pathExists(path)) return path;
    }
    return mole_candidates[0]; // always a path, even if missing
}
```

### Boot (`src/update.zig`)

```zig
pub fn boot(model: *Model, fx: *Effects) void {
    model.setMolePath(mole.resolveMole());
    mole.spawnStatus(...);
    mole.spawnHistory(...);
    ...
}
```

### Conventions

- Keep hardcoded Homebrew candidates as **first** priority (Apple Silicon / Intel).
- Then search `$PATH` for `mole`, then `mo`.
- Zig 0.16: do not use removed `std.fs.cwd()` APIs for arbitrary FS; existing `pathExists` in `mole.zig` uses `std.c.access` — reuse it for PATH entries.
- Env: prefer `std.posix.getenv("PATH")` if available in this Zig version; if not, use the SDK/Zig-documented equivalent. Do not panic if PATH is unset — skip PATH walk.
- Do **not** shell out to `which`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests | `native test --yes` | exit 0 |
| Check | `native check` | exit 0 |
| Build | `native build --yes` | exit 0 |
| Manual (optional) | `which mole`; run app | path matches discovery |

## Scope

**In scope:**

- `src/mole.zig` — discovery API
- `src/update.zig` — boot behavior when mole missing
- `src/model.zig` — only if you add a small flag e.g. `mole_found: bool` (prefer reusing `status_error` + `health_msg` to avoid markup churn)
- `src/tests.zig` — unit tests for resolution helpers that do not need a real binary
- `README.md` — one sentence under troubleshooting: PATH and Homebrew both supported
- `AGENTS.md` — one line on discovery order if the module table is updated

**Out of scope:**

- Bundling mole inside the app
- Version pinning of mole
- Changing spawn argv for jobs
- UI redesign beyond using existing error strings / badges

## Git workflow

- Branch: `advisor/003-mole-resolve-path`
- Commit example: `fix: resolve mole from PATH and surface missing binary at boot`

## Steps

### Step 1: Change the resolve API

Replace `resolveMole() []const u8` with something that can express "not found". Preferred shape:

```zig
pub const ResolveResult = struct {
    /// Absolute or candidate path to use for argv[0]; empty if not found.
    path: []const u8,
    found: bool,
};

pub fn resolveMole() ResolveResult
```

**Search order:**

1. Existing `mole_candidates` (Homebrew) via `pathExists`
2. Split `PATH` on `:` (Unix); for each dir, check `dir ++ "/mole"` then `dir ++ "/mo"` with `pathExists`
3. If nothing found: `found = false`, `path = ""` **or** keep a display placeholder but **do not spawn** with a fake path

Implementation notes:

- Building `dir/mole` needs a buffer (`std.Io.Dir.max_path_bytes` or `[std.fs.max_path_bytes]u8` if still available as deprecated alias).
- Return **string literals** or static candidate paths for Homebrew hits (stable pointers). For PATH hits, you must store the winning path into a **stable place**:
  - **Option A (simplest for this app):** write into a `threadlocal` or file-level `var resolved_path_buf: [max]u8` and return a slice into that buffer (document that resolveMole is not reentrant / call once at boot).
  - **Option B:** have caller pass a buffer: `resolveMole(buf: []u8) ResolveResult`.
  - Prefer **Option B** for clarity: `pub fn resolveMole(buf: []u8) ResolveResult`.

Update all call sites: `boot`, `initialModel` in `main.zig` (if it calls resolve).

**Verify**: project compiles after call-site updates: `native test --yes` may fail until boot logic is fixed — fix in Step 2.

### Step 2: Boot and initial model when missing

When `!result.found`:

- Set `model.mole_path` empty or set a short display like `"(not found)"` via `setMolePath`
- Set `model.status_error = true`
- Set `model.health_msg` to a clear string, e.g. `"Mole not found — brew install mole (or put mole on PATH)"`
- Set `model.status_loading = false` and **do not** call `spawnStatus` / `spawnHistory` (they cannot succeed)
- Still allow sudo probe or skip it — either is fine; prefer still running silent sudo probe only if harmless when idle

When `result.found`:

- `setMolePath(result.path)` and spawn status/history as today

**Verify**: with mole installed on the machine, `native dev` or binary still loads status. (If you cannot run GUI, `native test` + logic tests are enough.)

### Step 3: Tests

In `src/tests.zig` (or `mole.zig` test block):

1. **Unit-test path join / candidate preference** without requiring filesystem if possible:
   - Extract pure helper `fn joinPath(dir: []const u8, name: []const u8, buf: []u8) ?[]const u8` and test `"/opt/homebrew/bin" + "mole"`.
2. **Missing path behavior on model:** construct model as boot would when `found == false` and assert `status_error` and health message content (call a small `pub fn applyMoleMissing(model: *Model) void` if that keeps boot thin).

Do not write tests that delete the user's real mole binary.

**Verify**: `native test --yes` → pass.

### Step 4: Docs

README Troubleshooting table: add row — Mole installed but app says missing → ensure `which mole` works; app searches Homebrew paths then `$PATH`.

**Verify**: README mentions PATH.

### Step 5: Final gates

```sh
native test --yes && native check && native build --yes
```

## Test plan

- Pure path-join / resolve buffer tests
- Model flag + message when missing
- Pattern: `src/tests.zig` pure tests; do not break existing JSON tests

## Done criteria

- [ ] Homebrew candidates still preferred when present
- [ ] `$PATH` entries for `mole`/`mo` are searched when candidates miss
- [ ] When not found, no pointless status/history spawn; user-visible error string set
- [ ] `native test --yes` exit 0
- [ ] `native check` exit 0
- [ ] `native build --yes` exit 0
- [ ] README troubleshooting updated
- [ ] `plans/README.md` row 003 → `DONE`

## STOP conditions

- Zig 0.16 has no safe way to read PATH without Io that the app doesn't have in pure unit tests → still implement runtime PATH walk in `resolveMole`; unit-test only path join; do not block the feature.
- Changing `resolveMole` signature breaks SDK codegen unexpectedly → STOP and report compile error; keep a wrapper `resolveMolePath() []const u8` that returns `""` when missing if needed for one release.

## Maintenance note

If Mole is ever bundled next to the app binary, add that location **before** Homebrew candidates and document order in `AGENTS.md`.
