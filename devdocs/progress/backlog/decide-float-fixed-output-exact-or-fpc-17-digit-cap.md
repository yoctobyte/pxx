---
summary: "writeln(d:0:1) of a huge double: pxx and CPython print the EXACT value (18446744073709551616.0), FPC caps at 17 significant digits and zero-pads (18446744073709552000.0). Which is pxx's rule?"
type: decision
track: U
prio: 45
---

# Decide: fixed-format float output — exact, or FPC's 17-digit cap?

- **Type:** decision — **Track U**
- **Status:** open
- **Opened:** 2026-08-05
- **Raised by:** Track A, re-triaging
  `bug-a-aarch64-large-double-decimal-formatting`. Two of its three rows were a
  real aarch64 bug and are fixed; the third is this fork and was explicitly
  NOT decided.

## The fork

```pascal
var q: QWord; d: Double;
begin q := 18446744073709551615; d := q; writeln(d:0:1); end.
```

| | output |
| --- | --- |
| pxx (all five targets, after today's fixes) | `18446744073709551616.0` |
| **CPython** `f'{float(2**64):.1f}'` | `18446744073709551616.0` |
| **FPC** | `18446744073709552000.0` |

`18446744073709551616` is 2^64 — the **exact** value of that double. pxx and
CPython print it exactly; FPC rounds to 17 significant digits and pads the rest
with zeros.

## Why this is a decision and not a bug

pxx is not wrong here — it is *more* precise, and it agrees with CPython. The
ticket that surfaced it carries its own verification rule: *"require both FPC
and CPython to agree before trusting either."* They do not agree, so that row
was never evidence of a defect, and I closed it as re-triaged rather than
"fixing" pxx into being less exact.

But it is a real, observable divergence from FPC in ordinary output, and the
`compat` tag exists precisely for "behave like the reference implementation".
Someone has to say which rule pxx follows.

## Further evidence (2026-08-05): FPC has a THIRD behaviour at extreme magnitudes

Measured while re-triaging
`compat-pascal-write-fixed-huge-magnitude-differs-from-fpc`:

    1e20:0:2    pxx 100000000000000000000.00          FPC 100000000000000000000.00   AGREE
    1e30:0:3    pxx 1000000000000000140737488355328.  FPC 1000000000000000000020000000000.00
    1e300:0:5   pxx 99999999999999983567616651958...  FPC  1.0E+0300

Three things this adds:

- at 1e30 **neither** is the exact double — pxx prints the true value, FPC
  prints its own approximation, because **FPC computes in Extended**. So "match
  FPC" is not merely "print fewer digits", it is "reproduce Extended-precision
  intermediate results", which is a different and much larger promise;
- at 1e300 FPC **abandons the fixed form** and emits exponent notation
  (` 1.0E+0300`) despite `:0:5` asking for 5 decimals — a third behaviour, and
  one no option here had accounted for;
- the ordinary range already agrees exactly, so whatever is chosen only affects
  magnitudes past ~2^53.

That makes option 2 ("adopt FPC's cap") materially harder than it looked: a
17-significant-digit cap alone would still not reproduce the 1e30 row, and would
not produce the 1e300 fallback at all. A faithful option 2 is really "emulate
FPC's Extended-based formatter", which is worth stating plainly before anyone
signs up for it.

## Options

1. **Keep exact.** Every digit printed is a real digit of the value; matches
   CPython; needs no change. Cost: `writeln(d:0:1)` text differs from FPC for
   magnitudes past ~2^53, so a diff-based comparison against FPC output shows
   spurious mismatches forever, and any `compat` corpus has to special-case it.
2. **Adopt FPC's 17-significant-digit cap** for the FIXED form. Cost: pxx
   deliberately prints fewer true digits than it has, and the scientific form
   (`writeln(d)`) is already correctly rounded to 17 significant digits and
   matches FPC exactly — so the two spellings would follow different rules for
   different reasons, which wants writing down.

## Recommendation

Weak preference for **1 (keep exact)** — it is what the value IS, and the exact
decimal expansion added today makes it free. But this is a parity call about
user-visible output, which is Track U's, not an agent's.

Whichever way: the natural-form (`writeln(d)`) scientific output is already
FPC-exact and should not change. Only the `:w:d` fixed form is in question.
