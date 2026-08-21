---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`test_interface_arc_exc` reports `unwind freed=2` on i386, arm32 and aarch64 where x86-64 and FPC say 3. An interface reference held when an exception unwinds past its frame is never released on any cross target — one leak per unwind, silent."
status: working
owner: claude-A
---

# Exception unwind releases one interface too few on every cross target

- **Track A** (the four cross backends' unwind path / `exception_emit.inc`'s
  cross arms).
- Found 2026-08-21 by the 53-test dyn-array + interface cross differential.

## Measured

`test/test_interface_arc_exc.pas`:

| target | output |
| --- | --- |
| x86-64 | `reassign created=2 freed=2` / `caught` / **`unwind freed=3`** |
| i386 | ... / **`unwind freed=2`** |
| arm32 | ... / **`unwind freed=2`** |
| aarch64 | ... / **`unwind freed=2`** |
| riscv32 | `reassign created=2 freed=1` / `caught` / **`unwind freed=1`** |

i386, arm32 and aarch64 agree with each other and are short by exactly one, so
this is one missing release on a shared path, not three separate defects.
riscv32 is short on the reassign line too — that half belongs to
[[bug-a-riscv32-drops-interface-releases-in-six-shapes]]; only its unwind
shortfall is this ticket.

## Why it stays invisible

An unwind leak prints nothing. It surfaces only because this test counts
destructor calls, and the test is native-only in the Makefile — nothing runs it
for a cross target. The same reason
[[bug-a-no-dyn-array-scope-exit-release-on-four-backends]] survived.

## Where to start

x86-64's unwind releases the interface; compare its landing-pad cleanup against
each cross backend's. The scope-exit arm and the UNWIND arm are separate code
paths on every target — the scope-exit one was audited on 2026-08-21 and the
unwind one was not, which fits a count that is short by exactly one frame's
worth.

## Gate

`test_interface_arc_exc` printing `unwind freed=3` under `tools/run_target.sh`
on i386 / arm32 / aarch64; the 53-test cross differential no worse than
baseline; self-host fixedpoint + `tools/gate.sh quick`.
