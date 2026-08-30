---
prio: 40
track: A
type: refactor
blocked-by: []
summary: "The C preprocessor's include buffers are sixteen separate AnsiString globals in defs.inc, dispatched by two hand-written `case depth of 0..15` ladders in cpreproc.inc. That is one datum wearing sixteen names, it caps include nesting at 16, and until 2026-08-30 the missing `else` on the length ladder returned an UNASSIGNED function Result past the end. The undefined read and the dishonest guard are fixed; making it an array is what actually raises the limit, and the storage is Track A."
status: working
owner: frankS
---

# `CPrepInclude0..15` should be an array

## What exists

`compiler/defs.inc:3616`:

```pascal
  CPrepInclude0 : AnsiString;
  CPrepInclude1 : AnsiString;
  ...
  CPrepInclude15: AnsiString;
```

and in `compiler/cpreproc.inc`, two ladders that exist only to index them:

```pascal
procedure CPLoadInclude(depth: Integer);
begin
  case depth of
    0: LoadFile(CPrepPath, CPrepInclude0);
    ...
    15: LoadFile(CPrepPath, CPrepInclude15);
  end;
end;

function CPIncludeLength(depth: Integer): Integer;   { the same sixteen, again }
```

Plus a third `case` in `CPProcessInclude`. Three ladders, sixteen arms each,
all saying "the buffer at `depth`".

## What has already been fixed, so this ticket is not urgent

`bug-c-an-include-nested-deeper-than-16-is-silently-dropped` (frankC,
2026-08-30) closed the dangerous half **within Track C's files**:

- `CPIncludeLength` fell off the end of its `case` with `Result` never
  assigned, and the include search read that. Now `else Result := 0`.
- `CPInclude` guarded on `MAX_CPREP_INCLUDES = 128` while the table holds
  sixteen, so depths 16..127 reached a load that did nothing. It now refuses at
  the real limit with a message naming it.

So the silent wrong value is gone: 18-deep nesting used to print `0` where gcc
prints `17`, and now reports *"C include nesting too deep (the preprocessor has
16 include buffers; this include is at level 17)"*.

## What is left, and why it is worth doing anyway

**The limit is still 16, and it is close.** A model of the recursion over this
box's real header sets — deliberately over-estimating, since it counts
`#include`s inside conditional blocks the preprocessor skips — puts
`gtk/gtk.h`, the deepest set this repo compiles against, at **15**. One level.
Nothing hits the ceiling today and the failure is now loud rather than silent,
but the margin is a single header.

**And this is a textbook `normalise-dont-special-case` case.** Sixteen globals
and three parallel ladders are one datum wearing sixteen names; the missing
`else` was exactly the kind of defect a second (third) copy of a dispatch
harbours, and it went unnoticed for as long as the arms happened to agree. An
array deletes all three ladders and makes the limit one constant.

## Shape

`CPrepInclude: array[0..MAX_CPREP_INCLUDES-1] of AnsiString` in `defs.inc`,
with the three `case` ladders in `cpreproc.inc` collapsing to `CPrepInclude[depth]`.
Then `MAX_CPREP_INCLUDES` becomes the *true* limit and the extra guard added by
the ticket above can be deleted — it is deliberately the only line that needs
removing.

Watch the memory: sixteen AnsiStrings is nothing, 128 is still nothing, but
these hold whole preprocessed files and the array is global, so they are never
freed. If that matters, size the array to a real limit rather than to 128.

## What a fix must assert

- 16-deep nesting still compiles and gives gcc's values (already a test).
- Whatever the new limit is, one past it is the *nesting* diagnostic, not a
  dropped header (already a test; update the depth).
- A depth between 17 and the new limit now WORKS, which is the point.
- Self-host fixedpoint, and the gtk set — Pascal programs binding C headers
  reach this code hardest.

## Log
- 2026-08-30 — filed by frankC. The C-lane half (undefined read, honest guard,
  both tests) landed first; this is the storage change, which is Track A's.

## THIS NOW BLOCKS REAL-WORLD C — measured, frankC, 2026-08-30

The ticket reads as a tidiness refactor ("one datum wearing sixteen names").
It is not. **The 16-deep cap is a hard wall against real C code**, and it is the
FIRST thing hit — before a single line of a program is parsed.

Minimal repro, four lines, against upstream busybox 1.36.1 (`1a64f6a20`):

```c
#define _GNU_SOURCE 1
#include "autoconf.h"
#include "libbb.h"
int main(void){ return 0; }
```

```
pascal26:1: error: C include nesting too deep
              (the preprocessor has 16 include buffers; this include is at level 17)
```

`libbb.h` is busybox's aggregation header — every applet includes it, so this
blocks **all 145 translation units** of even a cat-only busybox build, not one
file. gcc compiles the same tree clean.

**It is cumulative depth, not one pathological header.** I checked the obvious
suspects individually and none of them reaches the cap on its own:

```
stdio.h  dirent.h  endian.h  byteswap.h  paths.h  libgen.h  sys/stat.h
   -- all compile fine, depth-limit-hit=0 for each
```

So there is no header to blame and no include to restructure. Real aggregation
headers simply nest deeper than 16 once glibc's own chains stack under them,
and busybox is not unusual in this.

### Why the obvious workaround is the wrong move

The depth could be shaved by giving `lib/crtl` its own `dirent.h`, `paths.h`,
`libgen.h`, `byteswap.h` etc. so the host glibc chain is never entered (the
compile emits a host-fallback warning for exactly those). **That is the
microfix**: it buys one corpus target, leaves the cap in place, and the next
real program hits it again a little deeper in. The cap is the root cause and the
array is the fix — as this ticket already says, and as `cpreproc.inc`'s own
comment predicted ("if the buffers ever become an array this line is the only
one to delete").

### Track C is standing on this and cannot fix it

`CPrepInclude0..15` are declared in **`compiler/defs.inc:3765`** — Track A's
shared file. Under Track C's rules ("anything in `lexer.inc`, `ir*.inc`,
`symtab.inc`, `defs.inc`, the backends → file a Track A ticket, do not edit it
under Track C") this is A's to make, so I am reporting rather than taking it.
The two `case` ladders in `cpreproc.inc` are mine and I will convert them the
moment the storage is an array; that half is mechanical.

Priority is not hand-edited here — [[feature-c-corpus-busybox-applet]] (p60) is
now marked `blocked-by` this ticket, so the ranker propagates 60 down the edge
on its own, which is the mechanism CLAUDE.md describes for exactly this.

---

## A THIRD defect under this ticket, and raising the cap was the TRIGGER, not the bug

Found by frankS while implementing, 2026-08-30. The ticket has now been
re-scoped twice — filed as tidiness, corrected by frankC to *"blocks all 145
busybox translation units"* — and this is the third layer.

`cpreproc.inc` carried a **second** depth-bounded table:

```pascal
CPPathAtDepth: array[0..17] of AnsiString;          { declaration }
if depth + 1 <= 17 then CPPathAtDepth[depth + 1] := CPrepPath;   { write site }
CPCurPath := CPPathAtDepth[depth];                  { read site — UNGUARDED }
```

The `<= 17` clamp on the write is **dead code**: nothing could reach depth 17
while the include buffers capped nesting at 16. The read at `CPProcessText` has
no bound test at all, and did not need one for the same reason.

**So the array's bound was correct only by the accident of a smaller bound
somewhere else.** Raise `MAX_CPREP_INCLUDES` to the real limit — which is the
entire point of this ticket — and `CPPathAtDepth[depth]` becomes an
**out-of-bounds read at depth 18**, on the path that runs for every single
`#include`. The dead clamp above it would silently stop recording paths from 18
on, so `-g` line markers would name the wrong file before the read went out of
bounds. Neither has a diagnostic.

**Raising the cap was the trigger, not the bug.** The bug was already there, in
the shape of a bound held up by an unrelated constant. This is why the fix sizes
`CPPathAtDepth` to `MAX_CPREP_INCLUDES` and deletes the clamp rather than
raising `17` to some new number: **one limit, spelled once**, so the class cannot
recur here rather than this instance of it being repaired.

frankA's phrasing, which is better than mine: *correct by convention, not by
construction — and it fails silently at the exact moment someone does the
obvious right thing.*

## Two stages, because the compiler cannot compile its own new source

`LoadFile(CPrepPath, CPrepInclude[depth])` did not compile:
`LoadFile expects string variables in IR codegen`. **Not a language limit** — an
ordinary `procedure F(var s: AnsiString)` accepts `arr[1]`, runs correctly and
matches FPC. The restriction was in the intrinsic (`specialId = 100`), which
matched its destination as a SYMBOL only.

- **Stage 1 — landed `4f73f88fa`, green.** `EmitLoadFileManagedAt` publishes to
  an ADDRESS, so an array element or a record field works. Under a bounded
  window from frankA, kept strictly inside the LoadFile lowering — the shared
  `EmitPublishManagedString` was not touched. Test
  `test/test_loadfile_into_element_and_field.pas` covers plain/element/field,
  asserts neighbouring slots are untouched, and republishes 50 times to exercise
  the release path (measured separately: 500 republishes of a 264 KB file peak
  at 512 KB RSS, where a leak would be ~132 MB).
- **Stage 2 — written, builds, fixedpoint `f812166486cd`, HELD.** Needs a pin
  first, and this was measured rather than assumed:

  ```
  $ ./stable_linux_amd64/default/pinned compiler/compiler.pas   # a fresh checkout
  pascal26:2053: error: LoadFile expects string variables in IR codegen
    in: compiler/cpreproc.inc
  ```

  Stage 2 builds on the implementer's box **only** because the binary on disk
  already carries stage 1. Pushing it would leave master unbuildable from the
  current pin for every fresh checkout, Track T's sweep clones included. This is
  the mirror of CLAUDE.md's documented seeded-tree trap: that one is a build
  that silently *succeeds* when it should have rebuilt; this is a build that
  succeeds **on one box only**. Same root property — the compiler on disk and
  the compiler the sources describe are two different things, and only running
  the *pinned* one tells you which you have.

  Pin requested from the coordinator rather than run here: it holds the repo-wide
  lock and Track A had an atomic two-file commit in flight.
