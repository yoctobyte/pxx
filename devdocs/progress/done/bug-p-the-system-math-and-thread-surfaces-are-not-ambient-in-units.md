---
summary: "`sqrt(x)` in a UNIT is `undefined variable` while the same call in a PROGRAM compiles — the ambient pull of `math` / `palthreadobj` only scans the program's own tokens"
type: bug
track: P
prio: 45
status: done
---

# The System math and thread surfaces are not ambient in units

- **Type:** bug (Pascal frontend / RTL reachability) — Track P
- **Opened:** 2026-08-27
- **Found by:** the FPC-compiler corpus march. `cutils.pas` stopped at line 463
  on `sqrt` being undefined, immediately after
  `bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed` moved it
  there from 331.

FPC declares `sqrt` / `ln` / `exp` / `sin` / `cos` / `arctan` / `pi` and the
low-level thread API (`BeginThread`, `TThreadID`, …) in the **System** unit, so
portable source calls them with no `uses` line at all. pxx keeps them in real
units — `math` (618 lines of correctly-rounded numerics) and `palthreadobj` (a
slot registry, a mutex and `TThread`) — that have no business being duplicated
into `builtin`, and instead pulls the unit in **ambiently** when a token scan
sees one of the names.

That scan lived only in `ParseProgram`, and it sees only the **program's** own
tokens. So the identical call compiled in a program and did not compile in a
unit.

## Repro

```pascal
unit uamb;
interface
function F(x: Double): Double;
implementation
function F(x: Double): Double;
begin
  F := sqrt(x) + ln(x) + exp(0.0) + arctan(0.0) + sin(0.0) + cos(0.0);
end;
end.
```

```
pascal26:8: error: undefined variable (sqrt)
pascal26:8: error: undefined variable (ln)
pascal26:8: error: undefined variable (exp)
pascal26:8: error: undefined variable (arctan)
pascal26:8: error: undefined variable (sin)
pascal26:8: error: undefined variable (cos)
```

FPC compiles it and prints `5.3863`.

This is the **third instance of one shape** — `textfile` (fixed as
`bug-textfile-primitives-not-ambient-in-units`) and the TObject root methods
were the first two, and both were patched into the same unit-level scan loop.
Per `devdocs/dev/root-cause-over-microfix.md`, *"two mechanisms is a smell,
three is a design flaw"*: the design flaw is that the ambient-pull rule is
written twice, once for programs and once for units, and every new System-unit
surface has to be added to both. Noted below.

## Fix

`compiler/pasparser_proc.inc`, `ParseUsesUnitBody` — the existing unit-level
token scan (~4300, the one already carrying `unitNeedsText` and
`unitNeedsRootMeth`) gains `unitNeedsMath` and `unitNeedsThreads` arms, with
pull sites beside the existing `textfile` pull. Triggers are copied exactly
from the program-level scan, comments and all:

- a following `(` for the six functions, so `var ln: Integer` does not drag
  35 KB of math into a unit that never calls it;
- bare for the paramless `pi`, which nothing distinguishes from a variable at
  this stage (a size cost, not a correctness one);
- `ThreadSafeMode` gating on the thread half, matching `ParseProgram`.

**Self-pull is already guarded.** A unit is entered into `CompiledUnits` at
`pasparser_proc.inc:3368`, *before* the token scan at ~4300, so `math` scanning
its own `sqrt` calls re-enters `ParseUsesUnitBody('math')`, hits the
already-compiled guard and exits. No new guard was needed; measured, not
assumed.

## Outcome — FIXED, 2026-08-27

- The repro compiles and prints `5.3863`, byte-identical to FPC 3.2.2.
- `test/units/uambientsys.pas` + `test/test_unit_ambient_system_surface.pas`
  (wired into `test-core` beside `test_thread_api_no_uses`) — a unit calling
  all seven math names with no `uses`, driven by a program that names no math
  at all so the program-level scan cannot see them. Output
  `a 5.0000|b 2.0000|c 12.5664|OK` is byte-identical to the FPC oracle. The
  `test-core` fragment was hand-substituted and run, since the quick tier does
  not reach `test-core`.
- The thread half was verified separately: a unit declaring `var t: TThreadID`
  compiled with `--threadsafe` now resolves it (`d 8`).
- **Corpus march: `cutils.pas` moves from line 463 to line 960**, where it now
  stops on `BsfQWord` — FPC's System bit-scan intrinsic, a different gap. For
  scale, the pinned compiler still stops at line 58.
- `gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
  fgl 7/7.

## Adjacent, deliberately NOT built (flagged, per scope discipline)

1. **`{$threadsafe on}` written inside a UNIT does not work.** The directive is
   processed when the unit is lexed, which is *after* `ParseProgram` decided
   whether to emit the thread runtime stubs, so the pull succeeds and the link
   then fails with `call to a runtime stub that was never emitted`. The flag
   form (`--threadsafe`) is fine, and is what the test uses. This is a
   driver/stub-emission ordering bug, not an ambient-pull bug, and wants its
   own ticket if anyone hits it.
2. **The two scans should be one routine.** `ParseProgram`'s scan
   (`pasparser_prog.inc` ~640-710) and `ParseUsesUnitBody`'s (~4300) now carry
   four duplicated name lists between them. Folding them into a single
   `ScanAmbientSurfaces(fromTok, toTok)` is the root-cause fix, but the two
   differ in where they may *act* (the program mints root-method rows at the
   end of pass 1, a unit must do it before its bodies parse), so it is a real
   refactor and not a quick-gate-only change. Filed as a smell here rather than
   done half-way.

## Log
- 2026-08-27 — resolved, commit 929832b10.
