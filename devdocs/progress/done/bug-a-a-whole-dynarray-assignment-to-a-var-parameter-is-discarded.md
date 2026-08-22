---
track: A
prio: 55
type: bug
blocked-by: []
summary: "FIXED 2026-08-22. On x86-64 ONLY, every whole-array assignment to a `var`/`out` DYNAMIC-ARRAY parameter was silently discarded — `d := e`, `d := nil`, `d := Copy(e)`, `d := F()`, `out` as well as `var`, from a nested routine too. IR_STORE_SYM's dynarray arm read and wrote [rbp+off] directly, which for a by-ref param holds the ADDRESS of the caller's handle, so it published the new handle over the callee's copy of the pointer and released the caller's slot address as if it were a heap block. SetLength and element stores always worked (IR_LEA has had the by-ref arm all along), which is exactly what made dynarrays through var look like they worked."
---

# A whole-dynarray assignment to a `var` parameter was silently discarded

- **Type:** bug (silent wrong value across a call boundary) — Track A
  (`compiler/ir_codegen.inc`, the x86-64 `IR_STORE_SYM` dynarray arm)
- **Status:** **fixed 2026-08-22**
- **Opened / closed:** 2026-08-22, found while building the differential for
  [[bug-a-an-out-parameter-of-a-managed-type-is-not-cleared]] — the natural way
  to clear an `out` dynarray is `d := nil`, and it did nothing.

## Measured

Thirteen shapes, each against fpc 3.2.2. Before the fix, on x86-64:

| shape | FPC | pxx |
| --- | --- | --- |
| `d := nil` | 0 | **5** |
| `d := e` | 2 | **5** |
| `d := Copy(e)` | 2 | **5** |
| `d := F_ret(4)` | 4 | **5** |
| `out d` (same assignment) | 2 | **5** |
| `array of AnsiString` | 2 | **5** |
| `SetLength(d, 3)` | 3 | 3 |
| `d[0] := 99` | 99 | 99 |
| `r.a := e` (dynarray FIELD) | 2 | 2 |

The bottom three are the reason this survived: the shapes people reach for first
all worked, so "dynamic arrays through `var`" looked fine.

## Root cause

`IR_STORE_SYM`'s dynarray arm reads the old handle from `[rbp+off]` and writes
the new one back to `[rbp+off]`. For a **by-ref parameter that slot holds the
ADDRESS of the caller's handle**, not the handle. So the store landed on the
callee's copy of the pointer — the caller's variable never moved — and the
"old handle" that was then passed to `PXXDynArrayRelease` was the caller's slot
ADDRESS being released as if it were a heap block.

`IR_LEA` has carried the by-ref arm all along (`SetLength`, indexing), and
`EmitPublishManagedString` carries the identical deref for the AnsiString case
**in the same file**. The dynarray arm beside it simply never got one.

## x86-64 ONLY — and that decided the fix

Measured before the fix on every backend: **i386, aarch64, arm32 and riscv32
were all CORRECT.** Only x86-64 was wrong.

That mattered, because the first fix attempted was the tempting one: change
`ir.inc` so a by-ref IDENT falls through to the address-based `IR_STORE_DYN`
arm that record FIELDS already use — "push it into the IR, all six backends get
it free" (`ir-as-substrate.md`). It worked on x86-64 and **broke aarch64 and
arm32 outright** (SIGSEGV), because their `IR_STORE_DYN` emits its address
operand without `InLValueWrite` and `IR_LEA` then answers the data pointer
instead of `&caller_slot`. Patching that took edits in four more backends — to
route around a defect that existed in exactly one.

So the IR was never the problem: five backends prove the shape was fine. The
whole fix is the missing deref, in the arm that was missing it. Confirmed by
rebuilding all four cross targets and diffing the emitted binaries against the
pre-fix build: **byte-identical on i386, aarch64, arm32 and riscv32.** (xtensa
refuses `SetLength` on a var-array param outright, a separate documented gap, so
the program does not reach this path there at all.)

The general lesson is the one `root-cause-over-microfix.md` states from the
other direction: *push generality down* is a rule about where a MISSING
capability belongs, not a licence to move a working mechanism because one
implementation of it is broken. Measure the other backends before concluding the
IR is at fault.

## Fixed

x86-64 `IR_STORE_SYM`, dynarray arm: when the symbol is `skParam` and `IsRef`,
load `rcx = [rbp+off]` once and do the old-load / publish through `[rcx]`. The
existing non-ref byte sequence is untouched, so nothing else in the compiler's
own output moved (self-host fixedpoint converged in one round).

## Verified

- `test/test_dynarray_assign_to_a_var_parameter.pas`, wired into `test-core`:
  the six broken shapes, the three controls, and an ARC row — 200 rounds of
  `d := e; d := nil` where `e` must survive with its contents intact, because
  without the retain that frees the block `e` still points at and nothing prints.
  **Byte-identical to fpc 3.2.2.**
- Leak/UAF: 400,000 iterations of `SetLength(d,64); d := nil; SetLength(d,64);
  d := e; d := nil` → **max RSS 392 KB, flat**, and `e` intact at the end.

## Still divergent, filed separately — NOT part of this fix

Two rows of the differential remain wrong on every backend and are older, other
bugs found by the same probe:

- `nested`: an assignment to the enclosing routine's by-ref dynarray param from
  a NESTED routine still does not reach the caller (5, FPC 2) — the nested body
  reaches `d` through the capture/display path, not as an `skParam`.
- `2d`: `SetLength(d, 2); d[0] := nil` on an `array of array of Integer` var
  param leaves `Length(d) = 0` where FPC gives 2.

## Gate

`make compiler/pascal26` (byte-identical fixedpoint, 1 round) + `tools/gate.sh
quick`, plus the four cross targets rebuilt and byte-compared as above.
