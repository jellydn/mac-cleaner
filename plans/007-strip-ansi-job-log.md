# Plan 007: Strip ANSI / control sequences from Mole job log lines

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Job lines currently go `job_line => model.appendLog(line.line)`
> in `src/update.zig`. Confirm that path still exists.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt / UX
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

Mole clean/optimize emit terminal colour and cursor control sequences. The app streams stdout **line-by-line** into a native text log. Users see garbled fragments (`[32m`, `ESC[...`) instead of readable status. Stripping ANSI keeps the TEA model simple and improves the Clean tab immediately.

## Current state

### Update path (`src/update.zig`)

```zig
.job_line => |line| model.appendLog(line.line),
```

### `appendLog` (`src/model.zig`)

Trims trailing `\r\n` only; no CSI/ANSI strip. Stores into `BoundedStr(220)` (truncation by design).

### Conventions

- Pure function preferred: `pub fn stripAnsi(input: []const u8, buf: []u8) []const u8` or write into a stack buffer then `appendLog`.
- Do **not** depend on third-party crates (none in this project).
- Call strip in `appendLog` **or** only on the job_line path so status strings you set manually are unaffected if they ever used intentional symbols — either is fine; stripping all appendLog input is simpler and OK if you never put real ANSI in your own messages.
- Support common CSI: `ESC [ ... letter` (parameter bytes `0x30-0x3F`, intermediate `0x20-0x2F`, final `0x40-0x7E`). Also strip lone `ESC` pairs that are OSC if easy; minimum is CSI `m` colour codes and cursor moves.
- Also strip `\r` mid-line if present (progress overwrites).

## Commands you will need

| Purpose | Command | Success |
|---------|---------|---------|
| Tests | `native test --yes` | exit 0 |
| Check | `native check` | exit 0 |
| Build | `native build --yes` | exit 0 |

## Scope

**In scope:**

- New helper in `src/model.zig` or `src/ansi.zig` (prefer small `src/ansi.zig` if >40 lines)
- `appendLog` or `update.zig` job_line path
- `src/tests.zig` pure strip tests
- `src/main.zig` test import if new file

**Out of scope:**

- Changing Mole flags to force plain output (nice extra if documented; not required)
- Full terminal emulator
- Unicode width / emoji issues

## Git workflow

- Branch: `advisor/007-strip-ansi-log`
- Commit example: `fix: strip ANSI sequences from job log lines`

## Steps

### Step 1: Implement `stripAnsi`

```zig
/// Copy `src` into `out` without ANSI CSI sequences. Returns the written slice.
pub fn stripAnsi(src: []const u8, out: []u8) []const u8
```

Algorithm sketch:

- i = 0, o = 0
- if byte == 0x1b and next is `[`, skip until final byte in `@`–`~`
- else if byte is other C0 controls except `\t` and `\n`, skip (or keep `\t`)
- else copy if room in out

**Verify**: unit tests with literals:

| Input | Output contains / equals |
|-------|---------------------------|
| `"hello"` | `hello` |
| `"\x1b[32mOK\x1b[0m"` | `OK` |
| `"a\x1b[1;31mb\x1b[0mc"` | `abc` |
| string longer than out | truncated safely, no panic |

### Step 2: Use strip in appendLog

In `Model.appendLog`:

1. Trim `\r\n` as today
2. Stack buffer e.g. `[220]u8` or `[512]u8`
3. `const cleaned = stripAnsi(trimmed, &buf)`
4. Store cleaned into LogLine

**Verify**: test that appendLog with ANSI results in content without ESC.

### Step 3: Final gates

```sh
native test --yes && native check && native build --yes
```

## Test plan

- Pure `stripAnsi` tests (required)
- One `appendLog` integration test on Model (required)
- Pattern: `bounded_str.zig` tests / `tests.zig` pure tests

## Done criteria

- [ ] ANSI colour codes do not appear in stored log lines
- [ ] Plain text unchanged
- [ ] `native test --yes` exit 0
- [ ] `native check` / `native build --yes` exit 0
- [ ] `plans/README.md` row 007 → DONE

## STOP conditions

- Mole has a documented `--no-color` / `NO_COLOR` that fully disables sequences **and** you can set it on spawn env — then prefer env **in addition** to strip, not instead of tests. Note: SpawnOptions may not support env; if no env field on spawn, strip-only is correct. Check SDK `SpawnOptions` before inventing env support.

## Maintenance note

If log line capacity increases, keep strip buffer ≥ LogLine capacity.
