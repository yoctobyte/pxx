---
summary: "`BeginThread` / `TThreadID` need `uses palthreadobj` while FPC declares them in `system` — portable threaded source does not compile as written"
type: bug
track: P
prio: 45
status: done
---

# The FPC low-level thread API needs a `uses` clause

- **Type:** bug (Pascal frontend / RTL reachability) — Track P
- **Opened:** 2026-08-27
- **Found by:** `tools/fpc_diff_probe.sh`, row `thread-beginthread`. Tagged
  `known` since 2026-08-09, when the ticket it pointed at
  (`compat-pascal-thread-api-surface-differs-from-fpc`) closed having built the
  API but left this half: *"What is left is the uses-clause wart"*. So the row
  has been a `known` with no OPEN ticket behind it, which the probe's own header
  calls a lie with a cost. This is the ticket.

## Repro

```pascal
{$threadsafe on}
uses {$IFDEF FPC} cthreads, {$ENDIF} SysUtils;
var Done: Integer;
function Body(p: Pointer): PtrInt;
begin Done := PtrInt(p) * 3; Result := 0; end;
var h: TThreadID;
begin
  Done := -1;
  h := BeginThread(@Body, Pointer(PtrInt(14)));
  WaitForThreadTerminate(h, 0);
  writeln(Done);
end.
```

FPC prints `42`. pxx: `error: unknown type: TThreadID`, then
`undefined variable (BeginThread)`. Adding `uses palthreadobj` makes it work, so
nothing about the API is missing — only its reachability.

FPC's `cthreads` is not the counterpart of `palthreadobj`: it picks the thread
MANAGER, while the names themselves come from `system`. A portable source
therefore names none of this, and must still compile.

## Shape of the fix

Exactly `math`'s: pull the unit on demand from a token scan, rather than
duplicating declarations into `builtin`. `palthreadobj` is a real unit with a
slot registry, a mutex and `TThread` itself — the same argument the math pull
records ("618 lines of correctly-rounded numerics that has no business being
duplicated into builtin"). The routines match with a following `(` like the math
names; `TThreadID` / `TThreadFunc` match bare, since they are written as types
and neither name is plausibly anything else.

**Gate the pull on threadsafe.** `palthread` refuses `__pxxclone` without it, so
an unconditional pull turns any program that merely CONTAINS the token
`BeginThread(` into a compile error about a runtime it never asked for. Without
threadsafe the names stay unknown, which is the honest answer — a non-threadsafe
build cannot start a thread.

## Gate

The probe row matches FPC and is untagged; a test in the FPC spelling (no uses
line); `uses palthreadobj` and `uses classes`+`TThread` both still work; a
program that mentions nothing thread-related is byte-identical;
`tools/gate.sh quick` + self-host fixedpoint.

## Outcome (2026-08-27)

Fixed as sketched. `ParseProgram` scans the token stream for the four routines
(each requiring a following `(`, like the math names) and the two type names
(`TThreadID` / `TThreadFunc`, matched bare — they are written as types and
neither is plausibly anything else), and calls
`ParseUsesUnitAmbient('palthreadobj')`. No declaration is duplicated anywhere.

The threadsafe gate is in, and it is load-bearing rather than a convenience: the
non-threadsafe answer is `unknown type: TThreadID` / `undefined variable
(BeginThread)` — the names simply stay unknown, which is honest, instead of a
program that merely mentions `BeginThread(` failing with palthread's
`__pxxclone requires --threadsafe` about a runtime it never asked for.

Verified: the FPC spelling compiles and matches FPC 3.2.2 row for row with no
uses line; `uses palthreadobj` still compiles unchanged; `uses classes` +
`TThread` still works (classes already aliases `TThread = palthreadobj.TThread`,
so the ambient pull cannot collide — it is the same unit); a program that
mentions nothing thread-related is untouched.

Test: `test/test_thread_api_no_uses.pas`. Probe row `thread-beginthread`
untagged, and it deliberately keeps FPC's own uses line — adding palthreadobj to
the `{$ELSE}` arm would hide exactly what the row now proves.

Gate: quick GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-27 — resolved, commit d0a8bf05a.
