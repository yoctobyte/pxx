---
track: A+S
type: bug
prio: 55
status: open
found: 2026-08-30
found-by: frankS
---

# Xtensa's scope-exit release handles ONE of seven managed kinds; every other backend handles all seven

`EmitManagedLocalCleanupForTarget` (`compiler/ir_codegen.inc:10680`) releases a
procedure's managed locals on the way out. It has one arm per target. Counting
the managed kinds each arm actually handles:

| arm | at `0f48fa6a9`, 2026-08-21 | at HEAD, 2026-08-30 |
| --- | --- | --- |
| i386 | 4 | **7** |
| arm32 | 6 | **7** |
| aarch64 | 7 | **7** |
| riscv32 | 3 | **7** |
| **xtensa** | **1** | **1** |

(x86-64 delegates to `EmitManagedLocalCleanup` in `symtab.inc` and is complete.)

Xtensa releases a scalar `AnsiString` and nothing else. Missing:
**COM interface, static array of managed, Variant, promo-int, record with
managed fields, dynamic array.**

## Measured

`test_managed_local_release_reuse` — which asserts by ADDRESS REUSE rather than
by counting, precisely because a leak prints nothing:

```
xtensa                                        x86-64 / riscv32
FAIL record with managed field  — leaked      ok   record with managed field
FAIL variant local              — leaked      ok   variant local
FAIL static array of string     — leaked      ok   static array of string
FAIL dynamic array of string    — leaked      ok   dynamic array of string
total ok 1 / 5                                total ok 5 / 5
```

`test_interface_arc` prints `freed=1` where the oracle says `freed=3` — the
COM-interface row, same arm, same cause.

Both are in the residual set of
[[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]] and are
the last two there that are not arithmetic or float.

## The finding worth more than the fix: CO-LOCATION MAKES DRIFT VISIBLE, ONLY AN ORACLE MAKES IT FAIL

`0f48fa6a9` (2026-08-21) gathered six per-target blocks into this one procedure
*specifically* to stop them drifting. Its own header says so:

> *"it used to be six blocks INSIDE those branches … and that shape is why the
> arms drifted … Bringing the call sites together does not merge the arms … but
> it does put them where a reader sees all six at once."*

In the nine days since, i386's arm went 4 → 7 and riscv32's went 3 → 7. Both
edits happened **inside this procedure**, with xtensa's one-row arm twenty lines
away and impossible to miss on screen. Nobody added a row to it.

The co-location did exactly what it promised and it was not enough, because
**seeing that an arm is short and being made to care are different events.**
The other five arms grew when a test went red. Xtensa's could not: nothing on
this machine could execute an xtensa binary until 2026-08-29/30.

That is the same sentence as [[why-xtensa-was-the-holdout]] arriving from a
sixth direction in one night, and this instance narrows it usefully: the earlier
five were cases where a search or a sweep could not SEE the gap. This one was
seen, or at least was sitting in plain view, four separate times. Visibility was
never the binding constraint. **The target with no oracle keeps the bug even
when the bug is on screen.**

## Fix

Port riscv32's six missing rows into the xtensa arm — it is the closest ABI
(32-bit, same helper set) and its arm is now complete. Verbatim, not
re-derived: four missing-row bugs were fixed on xtensa the same night by porting
rather than re-deriving, and a re-derivation is a second implementation.

`ir_codegen.inc` is shared Track A ground and a Track S stop-line, so this is
filed rather than fixed. The change is confined to the
`if TargetArch = TARGET_XTENSA then` block and touches no other arm, so it is a
good candidate for a scoped grant to whoever holds xtensa.

Gate when it lands: the two tests above green against the x86-64 oracle on both
ABIs, the 142-source differential with no regression, and `make
compiler/pascal26` (the self-host fixedpoint).

## Bound

Observable output plus a source-level count of the arms, hosted xtensa profile,
Call0, `--xtensa-soft-mulhigh`, at `37171a6b1`, against x86-64 and riscv32 built
from the same source. The per-arm table was produced by parsing the procedure at
both revisions, not by reading it. Windowed not checked; not checked on real or
emulated ESP silicon.
