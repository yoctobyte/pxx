---
track: A+S
type: bug
prio: 50
status: open
found: 2026-08-30
found-by: frankS
---

# The xtensa WINDOWED ABI bus-errors on frozen strings, Copy, and dynarray SetLength

Three constructs fault under `--xtensa-abi=windowed` and are correct under
Call0 (the default). All three predate the expression-stack fix in
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]] —
**verified against the pre-change compiler**, which bus-errors identically, so
this is not fallout from that work.

## Repro

`--target=xtensa --platform=posix --xtensa-abi=windowed --xtensa-soft-mulhigh`,
under `qemu-xtensa` 10.2.1. Each is correct on Call0 and on x86-64.

```pascal
program t; var a: string[8]; begin a := 'zz'; WriteLn(Length(a)); end.
{ Call0: 2    windowed: SIGBUS  -- no comparison, no concat: a frozen string alone }

program t; var s: AnsiString; begin s := 'abcdef'; WriteLn(Copy(s, 2, 3)); end.
{ Call0: bcd  windowed: SIGBUS }

program t; var i: Integer; a: array of Integer;
begin SetLength(a, 50); for i := 0 to 49 do a[i] := i * 3; WriteLn(a[49]); end.
{ Call0: 147  windowed: SIGBUS }
```

The frozen-string case is the one to start from: it is the smallest, it
involves no helper call that the other two share, and it says the fault is in
how a *frozen buffer's address* is formed under windowed rather than in `Copy`
or `SetLength` themselves.

## Why this is only visible now

Windowed is the ESP-IDF ABI, and nothing could run a hosted xtensa binary until
`feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle` landed the syscall,
exit and heap arms. On real IDF hardware these would have been three unexplained
crashes with no oracle to compare against.

**A caution for whoever takes it:** do not assume the windowed frame is the
suspect just because windowed is the failing arm. Call0 and windowed differ in
*two* independent ways — the register window, and the expression-stack direction
(`XtensaSlotOff`) — and the second was wrong on Call0 for months while windowed
was right. The arms are not "one correct, one broken"; they are two disciplines
that have each been wrong somewhere.

## Bound

Object-level plus observable output under qemu-xtensa 10.2.1, hosted profile,
both ABIs compared directly, at `e866cc16d4fe`. Not checked on real IDF
hardware.

## MEASURED 2026-08-30 (frankS) — TWO of the three were the data-section bug. `Copy` is NOT, and is still live.

All three repros run verbatim against the two builds that bracket
[[bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why]],
plus HEAD. Windowed, `--platform=posix --xtensa-soft-mulhigh`, qemu-xtensa:

| repro | `75d2ba662^` | `75d2ba662` | HEAD |
| --- | --- | --- | --- |
| `a: string[8]; a := 'zz'; WriteLn(Length(a))` | **SIGBUS** | `2` | `2` |
| `s := 'abcdef'; WriteLn(Copy(s, 2, 3))` | **SIGBUS** | **SIGBUS** | **SIGBUS** |
| `SetLength(a, 50); … WriteLn(a[49])` | **SIGBUS** | `147` | `147` |

`Copy` is deterministic (repeated), windowed-only — Call0 at HEAD prints `bcd`,
matching the x86-64 oracle.

### The frozen-string and SetLength arms are the DATA-SECTION alignment defect

They fault at the parent and pass at the child of a commit that touches
**`elfwriter.inc` only** — no backend, no IR — so nothing about how they are
CODED changed. They stopped faulting because the data section became 4-aligned.

**Not resolved, and this is deliberate.** They are green on a side effect of a
qemu performance fix, sized by `ELF_DATA_PAGE = 4096`; the alignment invariant
does not exist yet. Closing them would mark a live exposure resolved. They are
cross-referenced instead and go green for real when that ticket lands an explicit
invariant with a test.

### What this ticket is now ABOUT: `Copy` under windowed

One construct, still faulting at HEAD, which the alignment story does not
explain and never did.

**The ticket's own caution turns out to be the right one and is now evidence
rather than advice:**

> *do not assume the windowed frame is the suspect just because windowed is the
> failing arm … the arms are two disciplines that have each been wrong somewhere.*

Two of the three arms have now been explained by something that is not the
windowed frame at all — it is target-wide and hit Call0 programs too, just
fewer of them. Whatever is left in `Copy` is the residue after the loudest
shared cause was removed, which makes it a better-founded suspect than it was
when three constructs pointed three ways.

Starting point is no longer the frozen-string case (explained). It is `Copy`
itself: what address does the windowed arm form for the source or destination
buffer that the Call0 arm forms differently, given that a **frozen buffer alone**
(`string[8]`, no helper call) is now known to be fine at HEAD.

### Prio 40 → 50

Narrowed from three constructs to one, confirmed live at HEAD, and windowed is
the **ESP-IDF ABI** — the one real hardware uses — which has **no gated coverage
at all** ([[bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never]]).
Not higher, because `Copy` under windowed is not on the path of a current
milestone and Call0 is the default everywhere hosted.

### Method note

All three repros were run as written rather than the two the alignment
hypothesis predicted. Had the hypothesis picked, `Copy` would have been swept
into the alignment ticket and closed with the other two — a live SIGBUS filed as
fixed by a commit that does not fix it.
