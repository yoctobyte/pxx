---
prio: 50
track: C
type: bug
blocked-by: []
summary: "MAX_CPREP_INCLUDES is 128 and the nesting guard errors at 128, but CPLoadInclude/CPIncludeLength are `case depth of 0..15` with no else -- so at depth >= 16 the load is a no-op and CPIncludeLength returns an UNSET function result. Measured: the 17th nested header and everything below it vanishes, with no error. LEVEL16 came back 0 where gcc says 16, and the only diagnostic is `undeclared identifier ... treated as 0` pointing at the use site, nowhere near the dropped include."
status: new
owner: ""
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
