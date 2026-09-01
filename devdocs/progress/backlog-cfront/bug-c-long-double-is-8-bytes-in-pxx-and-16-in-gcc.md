---
track: C
prio: 35
type: bug
status: open
found: 2026-09-01
found-by: frankC
owner:
summary: "C `long double` is mapped to double (clexer.inc:342), so it is 8 bytes where gcc's is 16. MEASURED both sides: `struct { long double x; }` is sizeof 16 under gcc and 8 under pxx. Any such struct crossing a real C boundary therefore disagrees about its own SIZE before any calling-convention question is reached, and psABI puts an x87 member in MEMORY class where pxx would see one SSE eightbyte. Found by writing the NEGATIVE control for the new SysV classifier: the classifier's tyExtended refusal is unreachable from C because the frontend erases the distinction first, so a guard that looks like it covers long double cannot fire. Pre-existing and independent of the aggregate-classification work."
---

# `long double` is 8 bytes in pxx and 16 in gcc

`clexer.inc:342` says it plainly — *"l/L is long double, which we map to
double"*. That is a reasonable simplification for arithmetic and it is not one
for an ABI.

## Measured, both sides

```
gcc: sizeof(long double)=16   sizeof(struct { long double x; })=16
pxx:                          sizeof(struct { long double x; })=8
```

The disagreement is about the TYPE's size, so it precedes every
calling-convention question. A pxx callee reading a `long double` argument laid
down by gcc reads half of it; a struct containing one has the wrong size, the
wrong field offsets after it, and the wrong class (psABI puts an x87 member in
MEMORY; pxx sees a single SSE eightbyte).

## How it was found, because the method is the reusable part

Writing the NEGATIVE control for the new SysV classifier
(`ABISysVRecordEightbytes`, `abi.inc`) — the shapes it must REFUSE rather than
guess at. The refusal is keyed on `tyExtended`, and it never fired: the C
frontend has already turned `long double` into a double, so the oracle is asked
about an 8-byte SSE field and answers confidently.

**A guard that cannot fire, in code written the same hour, found only because
the control was written.** The guard is kept — it is correct the moment a
frontend produces `tyExtended`, and the Pascal frontend has that type — but its
comment claimed a coverage it does not have, and that is what was fixed.

## Scope

Narrow: C code using `long double` across a pxx/gcc boundary. tcc's float
constant parsing is the known real user (see
`done/bug-c-crtl-long-double-math.md`, a different problem — that one was the
missing `ldexpl` family, this is the type's width).

Not proposed here: implementing x87 80-bit. The cheap honest option is to
REFUSE `long double` in a by-value aggregate parameter rather than silently
disagree, which is a diagnostic and not a feature.
