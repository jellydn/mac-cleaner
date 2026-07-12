# External Integrations

**Analysis Date:** 2026-07-12

## APIs & External Services

**Subprocess / CLI engine:**

- Mole CLI (`mo`/`mole`) — the only external integration. The app spawns it as a subprocess (`fx.spawn`) for status, clean, optimize, and purge. Not a networked API; it is a local binary.
  - Invocations:
    - `mole status --json` -> `src/mole.zig:85` (status dashboard).
    - `mole history --json --limit 12` -> `src/mole.zig:99` (history tab).
    - `mole clean|optimize|purge [--dry-run]` -> built in `src/mole.zig:113` from `JobKind.fillArgv` (`src/model.zig:81`).
  - Path resolved at runtime from `/opt/homebrew/bin/mole`, `/usr/local/bin/mole`, `/opt/homebrew/bin/mo`, `/usr/local/bin/mo`, then `$PATH` (`src/mole.zig:11`, `src/mole.zig:48`). If missing: "Mole not found — brew install mole (or put mole on PATH)" (`src/mole.zig:70`).
  - SDK/Client: none (raw subprocess spawn, output parsed as JSON via `std.json` in `src/status_json.zig`).
  - Auth: none for Mole itself; an optional one-time local `sudo` session is granted via an `osascript` GUI password dialog (`src/scripts/grant-sudo.sh`, embedded `src/sudo.zig:12`) so subsequent `mole` children can `sudo -n`. This is local privilege elevation, not external auth.
- No other external APIs or SaaS services.

## Data Storage

**Databases:**

- None. No database engine, no ORM, no connection string.

**File Storage:**

- Local filesystem only. Mole operates on local system paths (caches, logs, trash, project build artifacts). The app itself keeps no persistent data store; status/history are read live from Mole's JSON stdout each refresh.

**Caching:**

- None at the app layer. A repeating 45s timer refreshes status while idle (`src/update.zig:59` + `src/update.zig:121`); a 30s sudo-keepalive timer re-issues `sudo -n -v` (`src/sudo.zig:15`, `src/sudo.zig:31`). No cache backend.

## Authentication & Identity

**Auth Provider:**

- None (no user accounts, no login, no tokens).
- Implementation: one-time local macOS admin (sudo) grant for system-level clean/optimize operations, obtained interactively via `osascript` password dialog; falls back to user-level Mole if not granted (`src/update.zig:147`, `src/sudo.zig:106`). Not an identity provider.

## Monitoring & Observability

**Error Tracking:**

- None. No Sentry/Datadog/telemetry. Errors surface in-app (status bar, error flags, log lines); e.g. spawn failures -> "Could not start mole" (`src/effect_handlers.zig:76`).

**Logs:**

- In-app job log buffer (up to 48 lines, `src/model.zig:273`). No external log shipping; no file logging.

## CI/CD & Deployment

**Hosting:**

- None. It is a native desktop binary; no hosting platform.

**CI Pipeline:**

- None configured (no GitHub Actions file yet). Local-only quality gates via `prek` Git hooks (`.pre-commit-config.yaml`) and `just` tasks: `native check`, `native test`, `zig fmt --check`.
- Gotcha: the repo currently has no commits, so `prek run --all-files` enumerates zero tracked files and SKIPS all hooks until files are committed (`prek install` + first commit makes them fire).

## Environment Configuration

**Required env vars:**

- None. The app reads no environment variables. Mole path is resolved by probing known absolute paths then `$PATH` (`src/mole.zig:48`).

**Secrets location:**

- None. No secrets, no credentials store. Optional sudo password is entered interactively in a GUI dialog and never persisted.

## Webhooks & Callbacks

**Incoming:**

- None. No HTTP server, no incoming webhooks (`external_links` action is `deny` in `app.zon:29`).

**Outgoing:**

- None. No outbound network calls. The only "external" action is spawning the local Mole/sudo subprocesses; no web requests, no webhooks, no APIs over the network.

---

_Integration audit: 2026-07-12_
