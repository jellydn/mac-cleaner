# Technology Stack

**Analysis Date:** 2026-07-12

## Languages

**Primary:**

- Zig 0.16 — All application logic, Mole subprocess effects, and JSON parsing. Modules under `src/` (`src/model.zig`, `src/update.zig`, `src/mole.zig`, `src/sudo.zig`, `src/status_json.zig`, `src/effect_handlers.zig`, `src/bounded_str.zig`, `src/main.zig`).

**Secondary:**

- Native SDK declarative markup (HTML-like `.native` DSL) — the entire UI lives in `src/app.native`, embedded into the binary via `@embedFile("app.native")` at `src/main.zig:49` and watched at `src/app.native` for hot reload (`src/main.zig:74`).

## Runtime

**Environment:**

- Native macOS desktop app (no browser/JS runtime). `app.zon:8` sets `.platforms = .{"macos"}`. Requires macOS 11+. GPU rendering via Metal (`app.zon:21`).

**Package Manager:**

- Native SDK CLI (`npm install -g @native-sdk/cli`) — manages build/run toolchain, auto-downloads pinned Zig 0.16.
- Homebrew — installs the external Mole engine (`brew install mole`).
- Lockfile: none (Zig packages `native_sdk`/`runner` imported directly; no manifest lock committed).

## Frameworks

**Core:**

- `native_sdk` — declarative UI, canvas, shell windowing, security/permissions, effects (`@import("native_sdk")` at `src/main.zig:6`).
- `runner` — app lifecycle / event loop (`@import("runner")` at `src/main.zig:5`).
- Zig standard library (`std`) — JSON, memory, formatting.

**Testing:**

- Native SDK headless harness (`native test`) — runs the `std.testing` suite in `src/tests.zig` (status/history JSON parsing, markup building, canvas layout, pure handlers).

**Build/Dev:**

- `native` CLI — `dev` (hot-reload), `test`, `build` (ReleaseFast -> `zig-out/bin/mac-cleaner`), `check` (validate markup + `app.zon`).
- `zig fmt` 0.16 — formatting enforced via pre-commit hook (`.pre-commit-config.yaml`).
- `prek` — Git-hook manager running `native check`, `native test`, `zig fmt --check`.
- `just` — task runner wrapping the above (`Justfile`: `build`, `dev`, `test`, `precommit`, `prek-install`).

## Key Dependencies

**Critical:**

- Mole CLI (`mo`/`mole`) — external system-cleaning engine spawned as a subprocess (`fx.spawn`). NOT a packaged/library dependency; resolved at runtime from Homebrew paths then `$PATH` (`src/mole.zig:11`, `src/mole.zig:48`). Missing -> `Model.mole_available = false` and "Mole not found — brew install mole" (`src/mole.zig:70`).
- `native_sdk`, `runner` — only code-level dependencies; imported directly, no lockfile.

**Infrastructure:**

- Homebrew — source for the Mole engine binary.
- `prek`, `just` — developer workflow / Git-hook tooling only; not shipped in the app.

## Configuration

**Environment:**

- `app.zon` — app identity, window config, permissions, security. Declares `permissions = .{ "view", "command" }` (the `command` permission enables subprocess spawning, `app.zon:9`) and `external_links` action `deny` (`app.zon:29`). No env vars, no secrets, no network config.
- No `.env`, no secrets store.

**Build:**

- `app.zon` — identity/window/permissions.
- `.pre-commit-config.yaml` — `prek` hooks (`native check`, `native test`, `zig fmt --check`).
- `Justfile` — `just` task wrappers (`build`, `dev`, `test`, `precommit`, `prek-install`).
- Build artifacts (gitignored): `.native/`, `zig-out/`, `.zig-cache/` (`.gitignore`).

## Platform Requirements

**Development:**

- macOS 11+.
- `brew install mole` (Mole engine must be present at runtime).
- `native` CLI installed (`npm install -g @native-sdk/cli`); it auto-downloads the pinned Zig 0.16 toolchain if absent.
- `prek` and `just` optional for Git hooks / convenience tasks.

**Production:**

- Native macOS desktop binary (`mac-cleaner`) targeting macOS 11+; bundles nothing but its own binary + `assets/icon.png`. No server, no backend, no cloud dependency. Mole must be installed on the end-user's machine.

---

_Stack analysis: 2026-07-12_
