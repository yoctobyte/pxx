---
track: A+S
type: bug
prio: 40
status: open
found: 2026-08-29
found-by: frankS
---

# Hosted xtensa segfaults on string concatenation, and bus-errors in Copy

Two distinct failures in the xtensa string runtime, both reachable from three
lines of ordinary Pascal, both invisible until tonight because **no hosted
xtensa program that allocated anything could run at all** — `HeapMmap` had no
`CPU_XTENSA` arm and every allocation faulted at `$FFFFFFFF` on a heap base of
-1 (see [[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]]). With the
heap arm in place the target gets far enough to fail in more interesting ways.

## Repro

Both under `qemu-xtensa` 10.2.1, `--target=xtensa --platform=posix
--xtensa-soft-mulhigh`, Call0. The flag is required for any numeric output — no
qemu core implements MUL32HIGH — and is not implicated in either failure.

```pascal
{ A: concatenation in a loop -> SIGSEGV }
program t; var i: Integer; s: AnsiString;
begin s := chr(97); for i := 1 to 20 do s := s + chr(120); WriteLn(Length(s)); end.
{ x86-64: 21   xtensa: SIGSEGV }

{ B: Copy -> SIGBUS }
program t; var s: AnsiString;
begin s := chr(97)+chr(98)+chr(99); WriteLn(Copy(s, 1, 2)); end.
{ x86-64: ab   xtensa: SIGBUS }
```

**What already works**, so the heap itself is not the suspect: `WriteLn` of an
Integer, `SetLength` on a dynamic array of 500 with element writes and reads,
simple AnsiString assignment and `WriteLn`, and ordered/equality string compare
(wrongly — that is
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]], a
different defect).

## Why two failure modes are worth one ticket

SIGSEGV and SIGBUS at different addresses suggest two bugs, and they may be. But
they are filed together because they share a suspect and whoever picks one will
be standing in front of the other: both are ANSISTRING PAYLOAD arithmetic —
concat writes a payload it just sized, `Copy` reads one at an offset — while the
constructs that work (dynarray, integer, whole-string assignment) never compute
an *interior* payload address. Split the ticket the moment the causes diverge.

## Do not assume it is the allocator

The tempting story is "the new heap arm is subtly wrong". Against it: the same
allocator serves the dynamic-array case, which allocates 2000 bytes and reads
back the last element correctly, and the simple string case. Measure before
believing the newest change — that is the trap
[[devdocs/dev/root-cause-over-microfix]] is about, and the heap arm is merely
the most recent thing to move.

## Bound on this verdict

Object-level plus observable program output under qemu-xtensa 10.2.1, from a
self-hosted fixedpoint build at `1ec7725af` plus the HeapMmap xtensa arm.

**Correction, same evening:** that arm was described here as unpushed, and it is
not — `git add -A` swept it into `dc62fe3cd`, the commit that filed this ticket,
which is why that commit is labelled `docs(S)` and contains compiler code. The
sentence is corrected rather than the history, because the sha is already cited
elsewhere and `master` is not rebased here. **So this IS reproducible on master
from `dc62fe3cd` onward**, which is the part that changes what a reader does.


---

## RESOLVED — frankS, 2026-08-30

**Both halves fixed on Call0 (the default ABI), and the ticket's own guess about
the cause was wrong in the useful direction.**

It said "do not assume it is the allocator" and pointed at interior ansistring
payload arithmetic. The payload arithmetic was fine. The cause was one level
further out: the managed-string arms addressed their EXPRESSION-STACK slots with
the windowed discipline (`sp + argBase + 4*idx`) while Call0 moves sp on every
push and never maintains `XtSpillDepth`, so every offset read a neighbouring
live slot. Concat's SIGSEGV and `Copy`'s SIGBUS were the same defect as
ansistring `=` returning a heap handle. Fixed in
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]] with
`XtensaSlotOff` / `XtensaDropSlots`.

Verified against the x86-64 oracle: concat x1, x20 and x200, and `Copy`, all
exact on Call0.

**What is left is NOT this ticket.** `Copy` still bus-errors under
`--xtensa-abi=windowed`, together with frozen strings and dynarray `SetLength` —
three faults that predate this work (the pre-change compiler bus-errors
identically) and are filed as
[[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]].

The instruction to split when the causes diverge is what happened, one direction
each: the two symptoms filed here turned out to share a cause with a *third*
ticket, and the windowed remainder turned out not to belong to any of them.
