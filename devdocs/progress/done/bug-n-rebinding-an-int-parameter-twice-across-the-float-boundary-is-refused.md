---
track: N
prio: 60
type: bug
owner: frank1-AN
blocked-by: []
summary: "`def f(x: int): x = x + 1; x /= 2` is refused with `annotate the type / too dynamic [a=28 b=19]` — a promotable int (28) joined against a double (19). Ordinary CPython code, refused at compile time. One rebind of either kind alone is fine; it is the PAIR that has no join."
status: done
---

# Rebinding an int parameter twice across the float boundary is refused

- **Type:** bug (Track N) — a compile refusal of working CPython code.
- **Found:** 2026-08-27 while resolving
  [[bug-n-augmented-true-division-does-not-widen-an-annotated-int-parameter]],
  whose fix made every single-rebind shape correct and left this one.
- **Measured:** identical at pinned **v383** (`18392d1d3181`) and at HEAD — the
  sibling fix changed neither the message nor the outcome.

## Repro

```python
def two(x: int):
    x = x + 1       # int + int can overflow -> a PROMOTABLE int (kind 28)
    x /= 2          # ...and true division wants a double (kind 19)
    return x
print(two(5))       # CPython 3.0
```

```
pascal26:3: error: Nil Python: annotate the type / too dynamic [a=28 b=19]
```

Either rebind ALONE is fine: `x = x + 1` alone returns 6, and `x /= 2` alone
returns 2.5 (as of the sibling fix). It is the pair that has no join.

## Where it comes from

`x = x + 1` on an int notes `tyPromoInt64` — deliberately, so an accumulator
stays exact past 2^63 — and `/=` then notes `tyDouble`. The widening join has no
answer for that pair and reports "too dynamic" rather than picking one.

The obvious answer is **variant**, which is what `PyWidenBinding` already gives
for an ordinary int-vs-float rebind and what a promo value boxes into anyway
(`VT_PROMO_INT64` carries the exact decimal). Whether the join belongs in
`PyWiden`, in `PyWidenBinding`, or at the promo-specific site is the thing to
measure — `TypeIsPromoInt` is deliberately excluded from `PyWidenBinding`'s
numeric arm today, and that exclusion is what routes this pair to the error.
Read that exclusion's reason before changing it.

## Gate

`two(5)` prints `3.0`, plus the same shape on a plain LOCAL (which must keep
whatever it does today) and on an accumulator that genuinely needs the promo
width (`x = x + 1` in a loop past 2^63, no float in sight — must stay exact).

## Resolution — the binding join was missing from the binding site

**Fix:** one line. `PyNoteLocalType` (pyparser.inc) joins with **`PyWidenBinding`**
instead of `PyWiden`, plus the promo arm that `PyWidenBinding` needed to answer
the pair.

`PyWidenBinding`'s own doc-comment states the concept: *"the join for a NAME
REBOUND across types — which is NOT the join for an EXPRESSION, and that
distinction is the whole fix."* It was wired into the module-local site
(27264), the field site (32869), the rebound-parameter site (24384) — and not
into `PyNoteLocalType`, the routine whose first line reads *"record one
assignment's RHS type against a local"*. So the per-def locals table asked the
**expression** join what a **rebinding** meant, and got `PyWiden`'s honest
"promo meets float has no scalar lowering; error honestly (annotate)".

Two joins for one concept, with the specific one absent from the most specific
site — `normalise-dont-special-case` in its usual costume.

`PyWidenBinding` then needed the promo pair itself:

```pascal
if (TypeIsPromoInt(a) and TypeIsFloat(b)) or
   (TypeIsPromoInt(b) and TypeIsFloat(a)) then
  Result := tyVariant
```

A variant loses nothing here: `VT_PROMO_INT64` is one of a variant's own tags
and carries the exact decimal past 2^63, so the slot becomes dynamic without
becoming lossy. The pre-existing comment calling this pair *"a deliberate honest
error rather than a silent boxing"* was right about the honesty and wrong about
the boxing.

## Two things this ticket asserted that measurement contradicted

Both are recorded because both cost a build cycle.

1. **"`TypeIsPromoInt` is deliberately excluded from `PyWidenBinding`'s numeric
   arm today, and that exclusion is what routes this pair to the error."**
   The exclusion existed — two `not TypeIsPromoInt(...)` clauses — and was
   **dead code**. `PyNumeric` lists the five machine numeric kinds and does not
   include `tyPromoInt64`, so `PyNumeric(a)` already implied `not
   TypeIsPromoInt(a)`. Deleting both clauses built clean and changed **nothing**:
   the repro failed with the byte-identical message. The refusal never came from
   there. Reading the exclusion's `git log -L` reason (`c787485a2`) was still the
   right move; believing the ticket about which line *fired* was not.

2. **"the same shape on a plain LOCAL (which must keep whatever it does today)"**
   — a plain local was refused **identically**:

   ```python
   def local_shape():
       y = 5
       y = y + 1
       y /= 2
       return y        # same error, same [a=28 b=19]
   ```

   That is the measurement that located the site. The bug was never in the
   parameter machinery; the parameter was just where it was first seen. What
   *does* have to keep today's behaviour is the neighbouring int-meets-float
   local (`z = 5; print(z); z = 3.14`), which must still print `5` and not
   `5.0` — verified, row 5 of the test.

## Gate — met verbatim, plus the siblings

- `two(5)` → `3.0` ✓ (CPython `3.0`)
- same shape on a plain LOCAL → `3.0` ✓, and on a FIELD → `3.0` ✓ (the field
  route already had the binding join; it now agrees with the local one)
- promo-width accumulator, no float in sight → `9223372036854775809` and
  `18446744073709551618`, exact ✓. Structurally safe, not just observed: the new
  arm requires exactly one FLOAT side, so an integer-only rebinding cannot reach
  it.
- `b //= 2` on the same doubly-rebound name still returns `4`, an int ✓ — only
  the float side wants a variant.
- 28 named promo/widen/infer canaries green (`widen_binding_variant`,
  `numeric_widen`, `int_promotion_default`, `promo_local_zero_init`,
  `def_returning_a_big_int`, `hex_bin_oct_bigint`, `true_division_return_type`,
  `module_true_divide_assign`, `floor_div_assign`, `a_rebound_parameter_widens`,
  `a_field_widens_across_methods`, `block_nested_rebind_widens`, …).
- self-host fixedpoint verified, `converged after 1 round(s)`.

**Test:** `test/test_nilpy_rebind_across_the_float_boundary.npy` (+`.expected`,
registered in the Makefile) — six rows: the parameter, the local, the field, the
exact accumulator, each-binding-renders-as-itself, and floor-div keeping intness.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
