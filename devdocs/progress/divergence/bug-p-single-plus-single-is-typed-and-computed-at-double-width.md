---
slug: bug-p-single-plus-single-is-typed-and-computed-at-double-width
track: P
prio: 40
type: bug
status: divergence
owner: ""
blocked-by: []
summary: "KNOWN DIVERGENCE, not a bug (owner, 2026-09-02). The measurement in this ticket is TRUE and reproducible; it is not a defect. Evaluating `Single + Single` at double width is a legitimate implementation choice and is strictly MORE accurate, and a program that stores the result in a Single gets FPC's exact bytes -- measured, `s := a + b` gives 0.300000012 on both. Nobody computes a wrong value. Two behaviours are CHOSEN, not tolerated, and neither compiler is wrong:  `SizeOf(a+b)` is 8 where FPC says 4, and an overloaded `P(a+b)` picks the Double arm where FPC picks Single -- both are TRUE statements about a pxx expression, exactly as FPC's answers are true about an FPC one; SizeOf reported correctly about the actual type, which is why the operator exists. A caller needing the narrow type writes `Single(a+b)`. Matching FPC would mean discarding precision we already have to reproduce its rounding, which is FPC-parity chasing rather than language conformance."
---

# Pascal `Single + Single` is typed Double

- **Found:** 2026-08-30 by frankA, as the cross-frontend control while fixing
  `bug-c-float-plus-float-is-computed-at-double-width`. The Pascal run was the
  row that was supposed to be *unaffected*.
- **Pre-existing**, not a regression from that fix: the C change touches
  `cparser.inc` only.

## Measured, FPC as oracle

```pascal
var a, b: Single; d: Double;
begin
  a := 0.1; b := 0.2; d := a + b;
  WriteLn(d:0:9);
  WriteLn(SizeOf(a + b));
end.
```

| | pxx | fpc `-Mobjfpc` |
| --- | --- | --- |
| `d := a + b` | `0.300000004` | `0.300000012` |
| `SizeOf(a + b)` | `8` | `4` |

`0.300000012` is the single sum; `0.300000004` is the double sum widened.

## Why the C fix does not port

The C ticket's own summary is the discriminator, and it is worth stating because
the two look like one defect:

- **C:** `sizeof(1.0f+1.0f)` was already **4**. The node's static type was
  right and only its *evaluation width* was wrong, so one `CNarrowSingle` call
  at the single site that tags a binop `tySingle` fixed every shape.
- **Pascal:** `SizeOf(a+b)` is **8**. The node is typed **Double**. Narrowing a
  node that claims to be a double is not the same change, and doing it would
  make the type and the value disagree in the other direction.

So the first question here is the TYPE RULE, not the width. Settle what
`Single + Single` should be typed as, and check what depends on the current
answer before changing `SizeOf` from 8 to 4 — that is an observable a program
can branch on.

## Not started

Filed with the measurement only. The C half is fixed and tested
(`test/c_float_arith_at_single_width.c`, gcc oracle, 17 rows, verified
byte-identical on x86-64, i386, aarch64, arm32 and riscv32).

## Related

- `bug-c-float-plus-float-is-computed-at-double-width` — the C half, fixed.
- `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` — the two
  frontends are *supposed* to answer this separately; that they answer it
  differently is not itself the defect, the wrong answer is.

## KNOWN DIVERGENCE 2026-09-02 — the measurement is right, the conclusion is not

This ticket asked the right question — *"settle the TYPE RULE"* — and the owner
has now settled it: **`Single + Single` evaluating at double width is correct,
and a programmer who wants the narrow type casts.**

Re-measured at `1d3da6ae9`, compiler sha256 `468194333634`
(`converged after 2 round(s)`, so a real rebuild and not the stamp path):

```
d := a+b     -> 0.300000004      (Double target: the double sum, MORE accurate)
s := a+b     -> 0.300000012      (Single target: FPC's exact answer)
SizeOf(a)    -> 4                (agrees with FPC)
SizeOf(a+b)  -> 8                (FPC: 4)
P(a+b)       -> picked DOUBLE    (FPC: picks Single)
P(a)         -> picked SINGLE
```

**The row that decides it is the second one.** Store the sum in a `Single` and
you get `0.300000012` — byte-for-byte FPC's answer. No program gets a wrong
value. The only way to reproduce FPC's `0.300000012` in a *Double* target is to
round to single precision and then widen, i.e. to deliberately throw away
precision we already have, in order to match another compiler's rounding. That
is FPC-parity chasing, which CLAUDE.md rules out: *on par with the LANGUAGE, not
with FPC.*

### Correcting the record on `SizeOf`

The disposition does NOT rest on "SizeOf reports it right". It does for the
variable (`SizeOf(a)` = 4) and it does **not** for the expression
(`SizeOf(a+b)` = 8, where FPC says 4). Stating the reason accurately matters,
because the wrong reason invites a refile the first time someone runs the
expression form.

### Two CHOSEN behaviours — and `SizeOf` was not diverging, it was working

Recorded as **chosen, not tolerated** (owner, 2026-09-02). Neither compiler is
wrong here and neither is more right:

1. **`SizeOf(a+b)` = 8 is TRUE.** It is a correct statement about the size of a
   pxx expression, exactly as FPC's 4 is a correct statement about an FPC one.
   Each reports its own compiler's representation faithfully — *"the programmer
   had all information it wants; sizeof reported CORRECTLY about the accurate
   type. that's why it exists — to not make assumptions."* A programmer who asks
   rather than assumes is served correctly by both compilers. **A truthful
   instrument returning an answer you did not expect is not a defect**, and this
   ticket read one as a defect because it expected the other number.

2. **Overload resolution picks the `Double` arm**, because the argument IS a
   double: `Single` is a storage type and double is the native evaluation type.
   The call is consistent with the expression's actual type rather than in spite
   of it.

The distinction between *chosen* and *tolerated* is the point of writing this
down. "We accept this divergence" concedes something was off and invites the
next reader to re-litigate it. "Both answers are correct about different
representations" closes it.

A caller who wants the narrow static type writes `Single(a + b)` — ordinary
Pascal, not a workaround.

### What would reopen this

Real source — not a probe — that is CORRECT under FPC and wrong under pxx
because of the expression's static type. Over-allocation and a more precise
overload do not qualify. Absent that, this stays closed.

The C half (`bug-c-float-plus-float-is-computed-at-double-width`) remains
correctly fixed and is untouched by this: there the node was already tagged
`tySingle`, so its evaluation width contradicted its own declared type. That is
an internal inconsistency, which is a real defect. Pascal has no such
contradiction — the node says Double and evaluates as Double.
