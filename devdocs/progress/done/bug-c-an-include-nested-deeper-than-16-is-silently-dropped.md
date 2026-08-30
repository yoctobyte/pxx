---
prio: 50
track: C
type: bug
blocked-by: []
summary: "MAX_CPREP_INCLUDES was 128 while CPLoadInclude/CPIncludeLength are `case depth of 0..15` with no else, so past depth 15 the load was a no-op and the LENGTH was an unassigned function Result -- the 17th nested header vanished with no diagnostic (LEVEL16 came back 0 where gcc says 16). FIXED 2026-08-30: `else Result := 0` and a guard that names the real limit, so it is now an error rather than a silent wrong value; both directions tested. The LIMIT is still 16 and is now bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array, because the buffers live in defs.inc."
status: done
owner: frankC
---

# An `#include` nested deeper than 16 is silently dropped

## Measured at `5ced3d9a0` (HEAD-built `compiler/pascal26`) and on `pinned`

Both arms agree, so this is not new — 24 headers, each `#include`ing the next,
each `#define`ing its own `LEVELn`:

| | `LEVEL14` | `LEVEL15` | `LEVEL16` | `LEVEL23` |
| --- | --- | --- | --- | --- |
| gcc | 14 | 15 | **16** | **23** |
| pxx | 14 | 15 | **0** | **0** |

pxx compiles clean and exits 0. The one diagnostic is
`warning: undeclared identifier 'LEVEL16' used as value (treated as 0)`, which
names the *use site* in `main.c` — nothing anywhere says an `#include` was
dropped, and the header that was dropped is 16 files away from the warning.

## Cause

`compiler/defs.inc`: `MAX_CPREP_INCLUDES = 128`, and `CPInclude` guards with

```pascal
if depth >= MAX_CPREP_INCLUDES then Error('C include nesting overflow');
```

so depths 0..127 are all "allowed". But the buffers are sixteen separate
globals dispatched by hand:

```pascal
function CPIncludeLength(depth: Integer): Integer;
begin
  case depth of
    0: Result := Length(CPrepInclude0);
    ...
    15: Result := Length(CPrepInclude15);
  end;              { <-- no else }
end;
```

At depth >= 16 `CPLoadInclude` does nothing and `CPIncludeLength` **falls off
the end of the case with `Result` never assigned**. The include search then
reads that unset value: if it happens to be non-zero the header is treated as
FOUND with empty content (what was measured — a silent drop); if zero, the
search reports "C include file not found" for a header that exists. Which one
you get is not a property of the program.

Two independent defects, and both should be fixed:

1. **The guard names a limit the implementation does not have.** 128 vs 16.
2. **A `case` with no `else` leaves a function Result undefined**, so the
   failure is unpredictable rather than merely wrong.

## How close is real code to the cliff? Measured, not guessed

The obvious objection is that nothing nests headers 17 deep by accident, which
would make the blast radius small. The counter-objection is that nobody has
looked, which would make it *unknown*. So I looked.

A faithful model of `CPProcessText`'s recursion (a header is entered at
depth+1 whether or not its guard then skips the body; an already-included
header costs one level and descends no further) over this box's real header
sets:

| header | modelled depth |
| --- | --- |
| `stdio.h`, `stdlib.h`, `string.h`, `math.h` | 6 |
| `time.h` | 5 |
| `glib.h` | 12 |
| **`gtk/gtk.h`** | **15** |
| `pango/pango.h` | 18 |

The model **overestimates**: it counts `#include`s inside conditional blocks
that the real preprocessor skips. That is the safe direction for "is the limit
reachable", and the `pango` row is where it shows — the chain it reports runs
`pango.h -> ... -> pthread.h -> sched.h -> linux/sched/types.h -> ... ->
asm-generic/bitsperlong.h`, and compiling a file that includes `<pango/pango.h>`
shows `__BITS_PER_LONG` **absent under gcc too**, so that chain is not actually
taken. I could not demonstrate any real header set here exceeding 15.

**So the honest reading is: not currently reachable, and one level of margin.**
`gtk/gtk.h` — the deepest header set this repo actually compiles against —
has a modelled upper bound of exactly 15, against a hard cliff at 16 with no
diagnostic on the other side. That is why this is prio 50 rather than the 45 it
was filed at or the 60 it was argued up to: the failure mode is severe and the
margin is one, but the claim "real code hits this today" is not supported by
measurement and should not be written into the ticket as if it were.

## Options

- **Make the buffers an array** — `CPrepInclude: array[0..N] of AnsiString` —
  and delete both hand-dispatched `case` ladders. This is the
  `normalise-dont-special-case` answer: the sixteen globals and their two
  ladders are one datum wearing sixteen names, and the ladders are exactly the
  kind of second path that stays broken. Raises the real limit to whatever N is
  and makes the guard honest for free.
- Minimum viable, if the array is too invasive: lower `MAX_CPREP_INCLUDES` to
  16 so the guard fires where the implementation actually stops, and add
  `else Result := 0` so the undefined-Result read cannot happen. This turns a
  silent wrong answer into a clear error, which is strictly better, but it
  leaves a 16-deep limit that real header sets can plausibly reach.

## What a fix must assert

- 24-deep nesting: `LEVEL16` and `LEVEL23` come back 16 and 23, matching gcc.
- Whatever the final limit is, exceeding it produces the *overflow error*, not
  a dropped header — i.e. the guard and the buffer count are the same number.

## Log
- 2026-08-30 — prio 45 -> 50 after measuring how close real headers get: gtk
  at a modelled (over-estimating) 15 against a cliff at 16. Argued for 60 on
  "blast radius unknown"; the measurement makes it known and narrow, so 50.
- 2026-08-30 — found by frankC while adding `__has_include`
  (`bug-c-has-include-unsupported-so-pdfgen-selects-big-endian`), which needed
  to know which include-buffer depths are safe to probe at. Filed rather than
  fixed: a different defect from the one being worked, and the buffer-array
  change wants its own gate.

## RESOLVED (the dangerous half) — 2026-08-30 (frankC)

Both defects the ticket names are fixed; the *limit* is unchanged and now has
its own Track A ticket, because the storage is not in this lane.

**1. The undefined read is gone.** `CPIncludeLength` was
`case depth of 0..15` with no `else`, so past the table it returned a function
`Result` that was never assigned — non-zero meant "found, with empty content"
and the header vanished; zero would have meant "not found" for a header that
exists. Which one you got was not a property of the program. Now
`else Result := 0`.

`CPLoadInclude` deliberately did **not** get an `else`, and the code says so:
it is a *procedure*, so falling off the end of its case leaves nothing
undefined. Adding one there would have implied a bug that was not there.

**2. The guard now names the limit that exists.** It tested
`depth >= MAX_CPREP_INCLUDES`, which is 128, against a table of sixteen — so
16..127 were "allowed" straight into a no-op. It now also refuses past 15, with
the count in the message:

```
error: C include nesting too deep
       (the preprocessor has 16 include buffers; this include is at level 17)
```

The `MAX_CPREP_INCLUDES` test is kept above it on purpose, so that when the
buffers become an array there is exactly one line to delete.

## Measured

| | pinned (pre-fix) | HEAD | gcc |
| --- | --- | --- | --- |
| 18-deep chain, reading `GL17` | compiles clean, prints **0** | **error naming the limit** | 17 |
| 16-deep chain, reading `GL0`/`GL15` | 0 15 | 0 15 | 0 15 |

The second row is the one that matters more: the fix must not move the boundary
it is making honest. Both are now in `test-core`.

**Nothing real trips the new error.** All five gtk tests green, and
`<pango/pango.h>` — the deepest set the model flagged — compiles with no nesting
diagnostic. That was the risk worth checking: turning a silent drop into an
error can only break something that was silently working, so I looked for it
rather than assuming.

## The limit itself is Track A

`CPrepInclude0..15` are sixteen separate globals in **`defs.inc`**, so the
array-ification this ticket proposed as its first option cannot be done here.
Filed as `bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array`
with the shape, the memory note, and the assertion list — including that the
extra guard added here is deliberately the only line that fix needs to delete.

Its prio is 40, below this one's 50, and that is the right way round: the
silent wrong value is fixed, so what remains is a ceiling that nothing currently
reaches. The margin is thin — `gtk/gtk.h` models at 15 against a limit of 16 —
but thin-and-loud is a different class of problem from silent.

## A test that failed for the wrong reason first

The 18-deep assertion greps the compiler's output for the diagnostic. Written
as `2> $(TESTTMP)/cnest18.err` it captured nothing, because **pxx prints
diagnostics on stdout**, so the grep failed against a compiler that was working
correctly. `> file 2>&1`, and the recipe carries the reason so the next person
does not re-derive it.

Validated in both directions, as the pair above shows: the assertion passes at
HEAD and would fail against `pinned`, which compiles the same source clean.

## Log
- 2026-08-30 — commit d5350d64a: undefined read and dishonest guard fixed by
  frankC, both tests in `test-core`; the limit itself handed to Track A.
  (Citation moved to the FRONT of the entry on purpose — third time tonight
  that a `commit PENDING-COMMIT` pushed onto a continuation line was invisible
  to the fill. The placeholder has to sit on the line the entry starts on.)
- 2026-08-30 — resolved, commit d5350d64a.
