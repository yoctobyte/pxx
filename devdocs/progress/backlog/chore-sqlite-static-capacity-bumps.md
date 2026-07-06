---
prio: 30  # auto
---

# sqlite arc — interim static capacity bumps

- **Type:** chore (capacity tuning) — Track A
- **Status:** backlog
- **Owner:** unassigned
- **Opened:** 2026-06-27
- **Relation:** interim/pragmatic counterpart to
  [[feature-dynamic-compiler-tables]] (the proper fix). Unblocks
  [[feature-c-desktop-lua-sqlite-path]] M5.

## Decision (user, 2026-06-27)

Static arrays are **fine for now**, even at a real RAM cost — bump the fixed
`MAX_*` caps as sqlite (the densest single TU) hits them. The dynamic-array
rework is explicitly **later** ([[feature-dynamic-compiler-tables]]). This ticket
just tracks the interim bumps so they are visible and re-pinnable as one unit.

## Bumps so far

- `MAX_TOKENS` 524288 → 2097152 (defs.inc). sqlite3.c (257k lines) overflowed
  512K tokens at ~52% of the file. 2M gives headroom. Cost: the token tables
  (`Tokens` + `TokPackRecords` + `CAttrFlags`, ~32 B/entry dominant) grow ~4×
  in static bss — acceptable for a desktop compiler (demand-zero pages).

## Expected next caps (watch as sqlite progresses)

`MAX_AST` (524288), `MAX_IR` (131072), `MAX_SYMS` (131072), `MAX_UFIELD`
(262144), `MAX_CTYPEDEF` (8192), `MAX_CPREP_MACROS`/`PARAMS`/`CHARS`,
`MAX_CODE`/`MAX_DATA`. Bump on the matching `Error('too many …')` / overflow.

## Landmine — each bump needs a pin cycle

Raising any `MAX_*` changes the compiler's own bss → the self-host build is no
longer byte-identical to the prior pinned binary. Each bump (or a batch) needs:
`make test` (self-host fixedpoint byte-identical with the *new* size) → stabilize
→ pin → commit `stable_linux_amd64/`. Batch bumps where possible to avoid churn.

## Acceptance

- sqlite compiles without hitting a fixed-table ceiling (semantic bugs filed
  separately, e.g. [[bug-c-invalid-symbol-in-lea-sqlite]]).
- The cap bumps are gated (`make test` + self-host byte-identical + cross) and
  pinned as a unit.
- Superseded/closed when [[feature-dynamic-compiler-tables]] lands for the
  affected tables.

## Log

- 2026-06-27 - Opened. `MAX_TOKENS` → 2M done (gating). User: static-now,
  dynamic-later. Track the remaining bumps here as the sqlite arc advances.
