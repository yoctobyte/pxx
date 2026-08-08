---
summary: "writeln(d:0:1) of a huge double: pxx and CPython print the EXACT value (18446744073709551616.0), FPC caps at 17 significant digits and zero-pads (18446744073709552000.0). Which is pxx's rule?"
type: decision
track: U
prio: 45
blocked-by: bug-a-write-fixed-emits-false-digits-past-1e22
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


## 2026-08-06 — the premise was FALSE; reframed and blocked

This was filed as "pxx prints the exact expansion, FPC prints a 17-significant-
digit approximation — which do we want?". Measured against the exact value of
the double (not against FPC), **pxx does not print the exact expansion**:

    1e30   pxx 1000000000000000140737488355328   exact 1000000000000000019884624838656
    1e300  pxx 99999999999999983567616651958...  exact 10000000000000000525047602552...

Correct through 1e22, wrong from 1e23 — and at 1e300 wrong from the first
significant digit. The integer part is expanded in `Double` arithmetic, so past
2^53 it leaks binary granularity into the output (`...2147483648` = 2^31,
`...140737488355328` = 2^47). Filed as
[[bug-a-write-fixed-emits-false-digits-past-1e22]].

**What that changes.** The fork was never "exact vs capped" — today it is
"false precision vs capped", and false precision is not a policy anyone would
choose. FPC's cap looks defensible precisely *because* the extra digits do not
exist. So:

- the option "keep printing the exact expansion" was **not available** as
  described. It becomes available only once the bug is fixed — and it genuinely
  can be, since `PxxSciDigits17` already expands a double exactly with base-10^9
  integer limbs and the fixed path simply does not use it;
- the option "adopt FPC's cap" is unchanged, and is now the *cheaper* of the
  two rather than the lesser one;
- FPC's third behaviour — abandoning the fixed form for exponent notation past
  ~1e300 — still has no counterpart here and still needs an answer either way.

Blocked on the bug. Deciding a display policy while the digits are wrong would
be choosing between two things neither of which we currently do.

## DECIDED 2026-08-08 (user): option 1 — KEEP EXACT

> the float issue is obvious. we are not cripling something we do correct and
> fpc doesn't.

**pxx prints the exact decimal expansion of the double in the fixed form.** It
does not adopt FPC's 17-significant-digit cap.

Reinforcing what the 2026-08-05 measurements had already shown: "match FPC" was
never merely "print fewer digits". FPC computes in **Extended**, so at 1e30 it
prints neither the exact value nor a 17-digit rounding of it, and at 1e300 it
**abandons the fixed form** for ` 1.0E+0300` despite `:0:5` asking for decimals.
Option 2 was therefore "emulate FPC's Extended-based formatter", a far larger
promise than its title, and one that would make pxx less correct to get there.

### Consequences

- The natural form `writeln(d)` is already FPC-exact and does **not** change.
  Only `:w:d` was ever in question.
- A diff-based comparison against FPC output will differ past ~2^53 forever.
  That is expected and correct; a `compat` corpus must special-case it rather
  than treat it as a defect. Note the claims-discipline rule in CLAUDE.md while
  writing any of that up.
- **Unblocks [[bug-a-write-fixed-fraction-digits-past-16-are-invented]]**, whose
  target is now unambiguous: the fraction must be the value's real digits, all
  of them, expanded exactly — not the current approximation, and not a cap. The
  machinery is already in the same unit (`PxxSciDigits17` expands a double
  exactly in base-10^9 limbs; the fixed path simply does not use it).
- The mirroring constraint stands: `PXXWriteFloatFixed` must keep matching the
  hand-emitted x86-64 `EmitWriteFloatFixed`, so the fix lands in both or the
  backends print different text. Routing both to one shared helper is the
  honest shape.
