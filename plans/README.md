# Advisor plans — Mac Cleaner

Index of implementation plans from **improve-code-architect** audits.

**Repo baseline:** often uncommitted; drift-check by comparing plan excerpts to live files.

**Verification (all code plans):**

| Purpose | Command | Success |
|---------|---------|---------|
| Tests | `native test --yes` | exit 0, all tests pass |
| Markup | `native check` | exit 0, `src/app.native: ok` |
| Release build | `native build --yes` | exit 0, binary under `zig-out/bin/mac-cleaner` |

## Status

| Plan | Title | Priority | Effort | Status |
|------|-------|----------|--------|--------|
| [001](001-effect-handler-characterization-tests.md) | Extract + test status/history/job effect handlers | P1 | M | DONE |
| [002](002-confirm-optimize-run.md) | Require confirm for `optimize_run` | P1 | S | DONE |
| [003](003-mole-resolve-missing-and-path.md) | Resolve mole via PATH; fail clearly when missing | P1 | S | DONE |
| [004](004-github-actions-ci.md) | CI: `native check` + `native test` on macOS | P2 | S | DONE (local only) |
| [005](005-gate-actions-when-mole-missing.md) | Gate actions when mole missing + Overview error | P1 | S | DONE |
| [006](006-sudo-handler-characterization-tests.md) | Characterization tests for sudo auth/ping | P1 | M | DONE |
| [007](007-strip-ansi-job-log.md) | Strip ANSI from job log lines | P2 | S | DONE |
| [008](008-docs-hygiene-and-first-commit-checklist.md) | Refresh stale `.planning` + first-commit notes | P3 | S | DONE |

Status: `TODO` → `IN_PROGRESS` → `DONE` | `BLOCKED`.

## Execution order (remaining)

```text
005  Gate actions when mole missing (+ Overview status error)
006  Sudo auth/ping characterization tests   (independent of 005)
007  Strip ANSI from job log                 (independent)
008  Docs hygiene / first-commit checklist   (independent; last is fine)
```

Recommended: **005 → 006 → 007 → 008**.

## Considered and rejected (do not re-plan without new evidence)

| Item | Why |
|------|-----|
| Silent `BoundedStr` truncation | By design for fixed UI model |
| Raising process/history caps | Product choice; mole `--limit 12` |
| Replace shell/osascript sudo with Authorization Services | Larger security project; matches Mole GUI pattern |
| Full `native package` / notarization | Direction, not a defect |
| Re-doing 001–004 | Already shipped |

## Audit waves

1. **2026-07-12 initial** — findings → plans 001–004 (executed).
2. **2026-07-12 follow-up** — findings 5–11 → plans 005–008 (this index update).
