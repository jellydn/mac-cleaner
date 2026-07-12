# Codebase Concerns

**Analysis Date:** 2026-07-12 (refreshed after modular layout)

Live modules: `src/main.zig`, `model.zig`, `update.zig`, `mole.zig`, `sudo.zig`, `effect_handlers.zig`, `status_json.zig`, `bounded_str.zig`. Prefer `AGENTS.md` for agent maps.

## Current concerns

1. **External Mole dependency** — App shells out to `mole`/`mo` (Homebrew then `$PATH`). Version is not pinned; schema drift breaks status/history parse. See `src/mole.zig`.
2. **Sudo via osascript + shell** — `src/scripts/grant-sudo.sh` pipes a GUI password into `sudo -S` (same class as Mole’s GUI path). Keepalive uses `sudo -n -v` only. Larger native Authorization Services work is intentionally deferred.
3. **Fixed-capacity UI strings** — `BoundedStr(N)` silently truncates long hostnames/error tails. By design for the TEA model; do not treat as a crash bug.
4. **List caps** — Top processes (8) and history (12) are fixed; mole history is requested with `--limit 12`.
5. **JSON parse allocator** — `status_json.zig` uses `page_allocator` per refresh (OK at 45s cadence).

## Not bugs

- Silent BoundedStr truncation and list caps are product choices.
- Plans 001–004 are shipped (effect handlers, optimize confirm, mole resolve, CI workflow).

## After large refactors

Either refresh this file against live paths or delete it so it cannot rot. Do not cite pre-split `main.zig` line numbers.
