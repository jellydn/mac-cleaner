# AGENTS.md — Mac Cleaner

Native macOS desktop app built on **Native SDK** (Zig 0.16 + `native_sdk`). The UI is declarative markup; the logic is Zig; the app drives the **Mole CLI** (`mo`/`mole`) by spawning it as a subprocess.

## Stack & mental model

- **Two separate CLIs** — don't confuse them:
  - `native` — the Native SDK build/run CLI (`npm install -g @native-sdk/cli`). Provides `dev`, `test`, `build`, `check`.
  - `mole` / `mo` — the cleaning engine. Install with `brew install mole`. Resolved at runtime from Homebrew paths under `/opt/homebrew/bin` and `/usr/local/bin`.
- `src/app.native` is the **entire UI**. Embedded via `@embedFile` and watched under `native dev`.
- Logic is split across modules (keep it that way):

| File                      | Role                                                          |
| ------------------------- | ------------------------------------------------------------- |
| `src/main.zig`            | App wiring only (`UiApp`, runner, re-exports)                 |
| `src/model.zig`           | `Model`, `Tab`, `JobKind`, `SudoPhase`, rows, view helpers    |
| `src/update.zig`          | `Msg`, `boot`, `update`                                       |
| `src/mole.zig`            | Mole path (Homebrew then `$PATH`) + status/history/job spawns |
| `src/sudo.zig`            | Session sudo grant + keepalive                                |
| `src/status_json.zig`     | Parse Mole status/history JSON                                |
| `src/effect_handlers.zig` | Pure status/history/job exit handlers (unit-tested)           |
| `src/bounded_str.zig`     | Fixed-capacity strings for model fields                       |
| `src/scripts/*.sh`        | Embedded grant/probe scripts                                  |

- `mole_available` on Model gates actions and spawns when Mole is missing.
- Job log lines pass through `stripAnsi` in `appendLog`.
- CI (`.github/workflows/ci.yml`) runs `native check` and `native test --yes` on macOS.
- `app.zon` needs the `command` permission for subprocesses.

## First commit / CI

1. `native test --yes && native check`
2. `git add` project files (not `.native/` / `zig-out/`)
3. `git commit -m "…"`
4. Optional: `prek install` so hooks run on commit
5. Push to GitHub so `.github/workflows/ci.yml` runs

## Commands

```sh
native dev     # Debug + hot-reload app.native
native test    # Headless suite
native build   # ReleaseFast → zig-out/bin/mac-cleaner
native check   # Markup + app.zon
```

## Job & sudo pipeline

1. Markup dispatches `start_*` → `requestJob`.
2. If `JobKind.needsConfirm()` → `confirm_job` dialog.
3. `sudo.ensureThen`:
   - purge / already active / boot probe in flight → start job
   - clean/optimize + inactive → interactive grant, then start
4. `JobKind` owns policy: `wantsSudo`, `needsConfirm`, `refreshesAfter`, `argv(mole)`.
5. `SudoPhase`: `unknown` → `inactive` | `active`, or `prompting` during dialog.
6. Keepalive every 30s via `sudo -n -v` while phase is `active`.

Do **not** reintroduce parallel bools (`sudo_active`, `sudo_auth_silent`, …). Use `SudoPhase`.

## Testing gotchas

- Tests assert literal UI strings from `app.native` (button labels, "Grant admin once", tabs).
- JSON tests live against `status_json.applyStatusJson` / `applyHistoryJson`.
- Policy tests cover `JobKind` and `sudo.ensureThen` phases.
- After structural changes run `native test` (refreshes model contract for `native check`).

## Artifacts

`.native/`, `zig-out/`, caches are gitignored — never commit them.
