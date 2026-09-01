---
type: bug
track: A
prio: 4
summary: passing a Variant that lives in a dyn-array record as an AnsiString parameter leaks about one block per call, but only after that array has been through SetLength — neither ingredient leaks alone
tags: [memory-leak, variant, dynarray, setlength]
---

Found while writing `test_record_variant_member_leaks`: the obvious spelling of
its assertion helper (`Chk(const got: AnsiString)` fed `a[1].v`) leaked, which
would have put an unrelated bug inside the bound of a leak test. The test now
compares inline and says why.

## The three measurements

1000 trips each, `-O2 -dPXX_ALLOC_CENSUS`, live blocks at exit:

    SetLength churn (4->8->2->5) AND read a[1].v via a
      `const s: AnsiString` parameter                      live=3663
    the SAME churn, reading only a[1].s (an AnsiString)    live=7
    the SAME read, no churn at all (SetLength once, read)  live=1

So neither ingredient leaks on its own — it needs the variant to be read through
an AnsiString parameter AND the array to have been resized. Roughly one block
per call: three reads per trip over 1000 trips is ~3000 of the 3663.

## Not the obvious suspect

A `Variant` read as an AnsiString from a plain LOCAL, or from an array element
without churn, allocates NOTHING at all — 200000 trips produce no census output
whatsoever. So this is not simply "the conversion temporary is unowned"; the
conversion does not normally allocate, and something about the post-SetLength
element makes it do so.

## Boundary NOT yet isolated

I did not narrow which SetLength does it (grow, shrink or regrow), nor whether
the read must follow the resize immediately, nor whether `var`/value parameters
behave differently from `const`. Anyone picking this up should start there
rather than in PXXVarClear — a leak that needs two unrelated ingredients usually
means one of them changed the element's representation, and finding WHICH resize
is a handful of probes.

## Partially reduced, not fixed, by the record-variant descriptor work

The same repro measures 3663 before that change and 921 after, so describing the
variant member to the record walk reclaims most of it and leaves a real residue.
Do not read the smaller number as this bug being nearly gone: it is the same
defect with fewer objects reaching it.
