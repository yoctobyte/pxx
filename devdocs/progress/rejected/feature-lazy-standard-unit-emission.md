# Lazy standard-unit emission / routine-level dead-code elimination

- **Type:** feature (compiler / codegen size)
- **Status:** backlog
- **Track:** A
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** follow-up to `feature-default-standard-units` (done). That change
  default-loads `textfile` + `builtin` into every non-ESP program; this ticket
  reclaims the size cost so the default surface can broaden safely.

## Problem

`feature-default-standard-units` made `textfile` (and its `builtin`
numeric-format backing) load by default. PXX has no dead-code elimination, so
**every** non-ESP program now emits the full textfile + builtin routine bodies
whether or not it does any file I/O. Measured cost:

- `test/hello.pas`: **29,086 → ~42,661 bytes** (+~13.5 KB, +47%).

This was an accepted tradeoff (user chose "always include textfile" over a
fragile per-use token scan), but it breaks the size guard in the parent ticket
and scales badly as the default standard surface grows (`System`, more RTL).

## Direction

- Add routine-level reachability: emit a unit's proc bodies only if reached from
  the program (transitively), not merely because the unit was `uses`-loaded.
  The proc/call graph already exists (`Procs[]`, `CallFix*`, `ProcAddr*`); the
  missing piece is a mark-and-sweep over reachable procs before emission, with
  the entry body + InitProcs as roots.
- Keep it deterministic (reachability derives from the stable call graph, not
  address/map iteration order) so `make bootstrap`/`cross-bootstrap` stay
  byte-identical. `-g`/debug paths unaffected.
- Watch the landmines: floating IR_CALLs need `IRIVal:=1` to emit; some builtin
  helpers are registered (hence "called") indirectly — those must count as
  roots, not be swept.
- Re-verify the size guard afterward: `test/hello.pas` should return to ~29 KB
  (no textfile routines emitted when no file I/O is used), with explicit
  textfile programs still complete.

## Acceptance

- `test/hello.pas` (no file I/O) emits no textfile/builtin routine bodies and is
  back at or near the 29,086-byte baseline.
- A program that uses `Text`/Assign/WriteLn still links and runs identically.
- `make test` green; `make bootstrap` + `cross-bootstrap` byte-identical.

## Log

- 2026-06-21 - Opened from `feature-default-standard-units`: default-loading
  textfile grew hello.pas 29,086 → ~42,661 bytes with no DCE. File this before
  broadening the default standard surface further.

## MERGED (2026-06-30 triage)

Redundant with the sibling emission-size ticket — both are reachability-gated DCE.
Merged into [[feature-emission-size-dce]]. Rejected here to avoid duplication.
