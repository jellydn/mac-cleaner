# Plan 004: Add GitHub Actions CI for native check and test

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check**: Confirm there is still no `.github/workflows/` directory (or
> update this plan if one already exists). Confirm local hooks in
> `.pre-commit-config.yaml` still list `native check` and `native test`.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW–MED (CI environment must have Zig/native tooling)
- **Depends on**: none (works best after the repo has at least one commit and a GitHub remote)
- **Category**: dx
- **Planned at**: uncommitted tree, 2026-07-12

## Why this matters

Local quality gates (`native check`, `native test`, `zig fmt`) exist only as optional `prek` hooks and a Justfile. The repository currently has **no CI**. Without a remote workflow, regressions land unchecked. This plan adds a macOS GitHub Actions workflow that runs the same commands developers use.

## Current state

### Local hooks (`.pre-commit-config.yaml`)

```yaml
- id: native-check
  entry: native check
- id: native-test
  entry: native test
- id: zig-fmt
  entry: zig fmt --check
  types: [zig]
```

### Justfile

```make
precommit:
    prek run --all-files
build:
    native build
dev:
    native dev
```

### Constraints

- App is **macOS-only** (`app.zon` platforms: `macos`). CI must use `runs-on: macos-latest` (or `macos-14`/`macos-15`).
- Tooling: Node (for `@native-sdk/cli`), Zig 0.16 (native CLI can download toolchain with `--yes`).
- Mole is **not** required for unit tests that mock JSON; if tests spawn mole they need `brew install mole`. Current `native test` suite does **not** require mole for the pure tests — verify with `native test --yes` on a machine without relying on network mole install if possible. Prefer CI without mole unless tests fail without it.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Local parity | `native test --yes` | exit 0 |
| Local check | `native check` | exit 0 |
| Fmt | `zig fmt --check src/*.zig` | exit 0 |

## Scope

**In scope:**

- `.github/workflows/ci.yml` (create)
- Optional: `README.md` badge line
- Optional: note in `AGENTS.md` under Commands: "CI runs `native check` + `native test` on macOS"

**Out of scope:**

- Windows/Linux CI matrices
- Deploy / release / notarization
- Installing Mole unless tests fail without it
- Changing app source (except if a CI-only flake requires a tiny fix — prefer STOP and report)

## Git workflow

- Branch: `advisor/004-github-actions-ci`
- Commit example: `ci: add macOS native check and test workflow`
- Push/PR only if operator asks

## Steps

### Step 1: Create `.github/workflows/ci.yml`

Use a workflow equivalent to:

```yaml
name: ci

on:
  push:
    branches: [main, master]
  pull_request:

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "22"

      - name: Install Native SDK CLI
        run: npm install -g @native-sdk/cli

      - name: native check
        run: native check

      - name: native test
        run: native test --yes

      - name: zig fmt --check
        run: |
          # Use zig from PATH if present; otherwise skip with warning only if native test already pulled a toolchain
          if command -v zig >/dev/null 2>&1; then
            zig fmt --check src/*.zig
          else
            # native may install zig under ~/.native/toolchains — try to find it
            ZIG=$(find "$HOME/.native/toolchains" -type f -name zig 2>/dev/null | head -1 || true)
            if [ -n "$ZIG" ]; then
              "$ZIG" fmt --check src/*.zig
            else
              echo "zig not found for fmt check; native test already validated compile"
            fi
          fi
```

Prefer making `native test --yes` the source of truth for compile+test. Do not fail the job solely because `find` is slow — cap find or use a known path if documented by native CLI.

**Simpler acceptable workflow** (if the above is too fragile):

```yaml
# only:
- native check
- native test --yes
```

Omit zig fmt in CI if locating zig is unreliable; local prek still covers fmt.

**Verify**: YAML is valid; files exist under `.github/workflows/`.

### Step 2: Document

Add to README under Commands or a new "CI" blurb:

```markdown
## CI

GitHub Actions (macOS) runs `native check` and `native test --yes` on push/PR.
```

**Verify**: README contains that sentence.

### Step 3: Local dry-run of CI commands

On the developer machine:

```sh
native check
native test --yes
```

Both must pass before merging the workflow.

**Verify**: exit 0.

### Step 4: (If remote exists) push and confirm green

If `git remote -v` shows a GitHub remote and the operator wants a push:

```sh
# only if instructed
git push -u origin HEAD
```

Watch Actions. If the job fails on missing Zig/native, fix the workflow install steps; do not weaken tests to greenwash.

If **no remote**, leave status DONE after local verification and note "workflow not yet executed on GitHub".

## Test plan

- No new Zig unit tests required.
- CI is verified by green workflow run or local command parity.

## Done criteria

- [ ] `.github/workflows/ci.yml` exists and runs on PR/push
- [ ] Job uses `macos-*` runner
- [ ] Steps include `native check` and `native test --yes`
- [ ] README documents CI
- [ ] Local `native check` + `native test --yes` pass
- [ ] `plans/README.md` row 004 → `DONE` (or `DONE (local only)` if no remote)

## STOP conditions

- GitHub-hosted macOS runners cannot install `@native-sdk/cli` (npm failure) → STOP; report log; suggest self-hosted runner or document manual-only checks.
- `native test` requires a display/GUI on CI and fails headless → STOP; report; do not disable the suite without a headless alternative.
- Operator has no GitHub repo → still add the workflow file; mark DONE (local only).

## Maintenance note

When adding new verification (e.g. `native build`), append a CI step rather than replacing tests. Keep CI commands aligned with `.pre-commit-config.yaml`.
