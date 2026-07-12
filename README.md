# Mac Cleaner

Native macOS cleaner dashboard built with [Native SDK](https://native-sdk.dev/) and driven by the [Mole](https://mole.fit) CLI (`mo` / `mole`).

No WebView, no Electron — declarative `src/app.native` UI + Zig logic, rendered by the Native SDK engine. Cleanup work runs as Mole subprocesses (`status`, `clean`, `optimize`, `purge`, `history`).

| | |
|---|---|
| **Platform** | macOS 11+ (arm64 / Intel) |
| **Stack** | [Native SDK](https://native-sdk.dev/) · Zig 0.16 · Metal |
| **Engine** | [Mole](https://mole.fit) (`brew install mole`) |
| **Binary** | ~4 MB ReleaseFast (`zig-out/bin/mac-cleaner`) |
| **License** | MIT |

## Screenshots / what you get

| Tab | What it shows / does |
|-----|----------------------|
| **Overview** | Health score, host & hardware, disk / memory / CPU / load / battery / trash, top processes |
| **Clean** | Dry-run or real **clean**, **optimize**, **purge** with a streaming job log |
| **History** | Recent Mole sessions (`mole history --json`) |

Status auto-refreshes every **45 seconds** while idle. After a real clean / optimize / purge, status and history refresh automatically.

## Prerequisites

- **macOS 11+**
- **[Mole](https://mole.fit)** — the cleaning engine this app wraps:

  ```sh
  brew install mole
  mole --version
  ```

- **[Native SDK CLI](https://native-sdk.dev/)** — build / run tooling:

  ```sh
  npm install -g @native-sdk/cli
  native version
  ```

- **Zig 0.16** — optional on PATH; `native dev|test|build` can download the pinned toolchain into `~/.native/toolchains/` if needed (`--yes` skips prompts).

## Quick start

```sh
# From this repo
native dev          # Debug build, open window, hot-reload src/app.native
```

Or build a release binary and run it:

```sh
native build
./zig-out/bin/mac-cleaner
```

## Commands

| Command | Purpose |
|---------|---------|
| `native dev` | Debug build + run; hot-reloads `src/app.native` |
| `native test` | Headless UI + JSON parse tests |
| `native build` | ReleaseFast binary → `zig-out/bin/mac-cleaner` |
| `native check` | Validate markup + `app.zon` (typed checks after `native test`) |
| `native package` | macOS app bundle (optional) |

## How it maps to Mole

This UI is a thin native front-end over the Mole CLI. From `mole --help`:

| In the app | Mole command |
|------------|----------------|
| Overview metrics | `mole status --json` |
| Clean · dry-run / run | `mole clean [--dry-run]` |
| Optimize · dry-run / run | `mole optimize [--dry-run]` |
| Purge · dry-run / run | `mole purge [--dry-run]` |
| History | `mole history --json --limit 12` |

**Left in the Terminal** (interactive TUIs, not driven here):

- `mo installer` — pick installer files to remove  
- `mo uninstall` — remove apps  
- `mo analyze` — disk usage explorer  

Mole is resolved at runtime from common Homebrew paths:

- `/opt/homebrew/bin/mole` (Apple Silicon)
- `/usr/local/bin/mole` (Intel)
- and the `mo` aliases next to those

If Mole is missing, Overview shows that it could not run Mole.

## Safety

- Prefer **· dry-run** first — preview only, no deletions.
- **Clean · run** and **Purge · run** show a confirm dialog before spawning Mole.
- **Admin once per session:** on the Clean tab use **Grant admin once**, or start a clean/optimize job. A single macOS password dialog appears; the app then refreshes the sudo timestamp every 30s so Mole does not ask again while the app is open.
- If you cancel the dialog, clean/optimize still run at **user level** (system caches skipped).
- The app has the Native SDK `command` permission so it can spawn Mole; external links are denied in `app.zon`.

## Project layout

```
.
├── app.zon                 # App identity, window, permissions
├── assets/icon.png
├── src/
│   ├── app.native          # Entire UI (markup)
│   ├── main.zig            # UiApp wiring only
│   ├── model.zig           # Model, JobKind, SudoPhase, rows
│   ├── update.zig          # Msg + boot/update
│   ├── mole.zig            # Mole path + spawns
│   ├── sudo.zig            # Session admin grant + keepalive
│   ├── status_json.zig     # status/history JSON parsers
│   ├── bounded_str.zig     # Fixed-capacity strings
│   ├── scripts/            # Embedded grant/probe shell
│   └── tests.zig
├── AGENTS.md
└── LICENSE
```

### Architecture (short)

```
Events → Msg → update → Model → app.native
                 │
                 ├─ mole.spawn*(…)
                 └─ sudo.ensureThen / grant / keepalive
```

- Markup never mutates state; all changes go through `update`.
- `JobKind` owns confirm / sudo / argv / refresh policy.
- `SudoPhase` is the only sudo state (`unknown` → `inactive` | `active`, or `prompting`).

## Development

```sh
native check    # markup + manifest
native test     # full headless suite
native dev      # iterate on UI with hot reload
```

Tips:

- Edit `src/app.native` while `native dev` is running — the window updates without losing model state.
- Renaming button labels may require matching string updates in `src/tests.zig`.
- Build outputs (`.native/`, `zig-out/`, caches) are gitignored; do not commit them.

## Packaging

```sh
native build
native package --target macos
```

See [Native SDK packaging](https://native-sdk.dev/packaging) for signing and distribution options.

## CI

GitHub Actions (macOS) runs `native check` and `native test --yes` on push/PR.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| “Could not run mole” / “Mole not found” | `brew install mole` and confirm `which mole` works — the app searches Homebrew paths then `$PATH` |
| Status empty / error | Run `mole status --json` in Terminal; check Mole version |
| Clean incomplete for system caches | Use **Grant admin once** in the app, or `sudo -v && mo clean` in Terminal |
| Build fails on Zig stdlib | Use Zig **0.16** (or let `native` fetch it) |
| Markup errors | `native check` prints `file:line:column` diagnostics |

## License

[MIT](./LICENSE) © 2026 Dung Huynh Duc

---

**Links:** [Native SDK](https://native-sdk.dev/) · [Mole](https://mole.fit) · [Mole on GitHub](https://github.com/tw93/mole) (if applicable to your install source)
