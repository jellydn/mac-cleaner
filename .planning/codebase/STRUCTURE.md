# Codebase Structure

**Analysis Date:** 2026-07-12

## Directory Layout

```
mac-cleaner/
├── app.zon                      # App identity, window, permissions, capabilities
├── README.md                    # Project overview
├── AGENTS.md                    # Agent / conventions guide
├── Justfile                     # build/dev/test/precommit/prek-install task aliases
├── .pre-commit-config.yaml      # native check/test + zig fmt hooks (prek)
├── LICENSE
├── assets/
│   └── icon.png                 # App icon (referenced by app.zon + main)
├── src/
│   ├── main.zig                 # Wiring only: entry main(), Model/Msg re-exports, runner setup
│   ├── model.zig                # State: Model, Tab, JobKind, SudoPhase, row structs, helpers
│   ├── update.zig               # Msg union, makeUpdate, boot(), update(), job/sudo orchestration
│   ├── mole.zig                 # resolveMole() + spawnStatus/spawnHistory/spawnJob/cancelJob
│   ├── sudo.zig                 # sudo grant/keepalive/probe (embeds scripts/*.sh)
│   ├── status_json.zig          # applyStatusJson/applyHistoryJson/pickRootDisk
│   ├── effect_handlers.zig      # Pure status/history/job exit handlers (unit-tested)
│   ├── bounded_str.zig          # BoundedStr(n) fixed-capacity string type
│   ├── tests.zig                # std.testing suite (markup build + JSON parse + UI strings + unit)
│   ├── app.native               # Entire declarative UI markup (embedded in main.zig)
│   └── scripts/
│       ├── grant-sudo.sh        # Interactive admin-password dialog (osascript)
│       └── probe-sudo.sh        # Silent sudo-timestamp probe
├── .planning/
│   └── codebase/                # Planning docs (STACK/INTEGRATIONS/ARCHITECTURE/STRUCTURE/CONVENTIONS/TESTING/CONCERNS)
├── .native/                     # Native SDK build cache (generated, gitignored)
├── zig-out/                     # Build output binary (generated, gitignored)
└── .zig-cache/                  # Zig compiler cache (generated, gitignored)
```

## Directory Purposes

- **src/:** All application logic and UI (Zig modules + markup). Key files: `src/main.zig`, `src/model.zig`, `src/update.zig`, `src/mole.zig`, `src/sudo.zig`, `src/status_json.zig`, `src/effect_handlers.zig`, `src/bounded_str.zig`, `src/app.native`, `src/tests.zig`.
- **assets/:** Static app icon (`assets/icon.png`).
- **src/scripts/:** Shell scripts embedded into the binary for sudo handling (`src/scripts/grant-sudo.sh`, `src/scripts/probe-sudo.sh`).
- **.planning/codebase/:** Architecture / structure / stack / integration / conventions / testing / concerns notes.
- **.native/, zig-out/, .zig-cache/:** Generated build artifacts, gitignored (do not commit).

## Key File Locations

- **Entry Points:** `src/main.zig:67` (`main`), `src/main.zig:51` (`initialModel`), `src/main.zig:49` (markup embed).
- **Configuration:** `app.zon` (identity/perms/window); `src/app.native` (UI); `src/scripts/*.sh` (sudo).
- **Core Logic:** State `src/model.zig`; update/effects `src/update.zig`; Mole `src/mole.zig`; sudo `src/sudo.zig`; JSON `src/status_json.zig`; pure handlers `src/effect_handlers.zig`; strings `src/bounded_str.zig`.
- **Testing:** `src/tests.zig` (asserts literal UI strings from `src/app.native`).

## Naming Conventions

- **Files:** `snake_case.zig` (e.g. `main.zig`, `status_json.zig`, `bounded_str.zig`); `src/scripts/*.sh` for embedded shell.
- **Types:** PascalCase structs/enums — `Model`, `Msg`, `Tab`, `JobKind`, `SudoPhase`, `ProcessRow`, `HistoryRow`, `LogLine`.
- **Functions:** snake_case — `applyStatusJson`, `resolveMole`, `spawnStatus`, `ensureThen`, `handleAuthDone`, `pickRootDisk`.
- **Enums:** `Tab` (`overview/clean/history`), `JobKind` (`clean_dry/clean_run/...`), `SudoPhase` (`unknown/inactive/prompting/active`).
- **Markup:** kebab-case tags/attributes (`<column>`, `on-press`, `window-drag`); `{helper}` bindings and `on-press="msg"` handlers in `src/app.native`.
- **Generics:** `BoundedStr(comptime n)` in `src/bounded_str.zig:5`.

## Where to Add New Code

- **New Feature (state):** Add fields + helper methods to `src/model.zig` (struct at `src/model.zig:204`).
- **New Messages:** Extend the `Msg` union in `src/update.zig:13` and handle them in `update` (`src/update.zig:79`).
- **Spawning / effects:** Mole calls go in `src/mole.zig`; admin calls in `src/sudo.zig`; orchestration in `src/update.zig`.
- **UI / text:** Edit `src/app.native` — literal strings (tab labels, button labels like "Open Clean", "Clean · dry-run", "Grant admin once") are asserted by `src/tests.zig`; update the test literals to match.
- **JSON parsing:** Extend `src/status_json.zig` (`applyStatusJson` / `applyHistoryJson`).
- **Pure exit mutations:** Put them in `src/effect_handlers.zig` so they unit-test without `Effects`.

## Special Directories

- **.native/:** Native SDK cache. Generated: yes. Committed: no (gitignored).
- **zig-out/:** ReleaseFast binary (`mac-cleaner`). Generated: yes. Committed: no.
- **.zig-cache/:** Zig compiler cache. Generated: yes. Committed: no.

---

_Structure analysis: 2026-07-12_
