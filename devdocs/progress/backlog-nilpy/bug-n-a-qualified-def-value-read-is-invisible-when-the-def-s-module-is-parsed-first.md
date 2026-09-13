---
slug: bug-n-a-qualified-def-value-read-is-invisible-when-the-def-s-module-is-parsed-first
title: a qualified def value read is invisible when the def's module is parsed first
summary: >
  `mod.f` read as a VALUE from another module normalises `f` to the callable ABI
  only when the READING module's tokens already exist. PyDefUsedAsValue scans
  [0, MainProgramTokCount), and MainProgramTokCount is re-pointed to whichever
  module is being parsed, so a read in a module lexed LATER is not in range. When
  the program imports the def's module first, `f` keeps its concrete return type
  and its annotated parameter types: a container result comes back as a raw
  pointer and an annotated `list` parameter SEGFAULTS. Silent wrong value, decided
  by import order. The order-independent fix is a return KIND (and parameter
  kinds) on the signature record so the pair bridge marshals like PyHostCall
  does, rather than a pre-scan the parse order can defeat.
track: N
type: bug
prio: 60
owner: unassigned
status: open
---

## Measured 2026-09-13 (frankH), at the tree carrying the module-qualified fix

`fec1abd13`'s sibling: the qualified value read now normalises the def
(`test_nilpy_a_module_qualified_def_is_a_value*.npy`), but only where the scan
can SEE the read. Two reductions, four files each, both in one import order and
correct in the other.

**The return side.** `retkinds.npy` holds `def r_three(): return ([1], [2], {"m": 3})`;
`retkreader.npy` does `Holder(details=retkinds.r_three)` and calls it back through
the field, exactly as lekkerzeilen's `vessel.py:604` does:

    import retkinds          # the program imports the DEFS' module first
    import retkreader        # ...and the reader second
    print(retkreader.three().fittings())

    CPython   ([1], [2])
    pxx       TypeError: expected a str, list, dict or bytes, got int

Reverse the program's two imports — or drop the first, so the reader pulls the
defs in itself — and it is correct. That is what
`test_nilpy_a_module_qualified_def_is_a_value_across_modules.npy` does, and it is
written that way ON PURPOSE with this ticket named beside it: a fixture that
passes in one order and fails in the other must not be spelled in the order that
passes (CLAUDE.md, the ordered-list rule).

**The parameter side, which is worse.** Same order, annotated parameters:

    # ga.py
    def g(x: int):   return x + 1
    def gs(s: str):  return s + "!"
    def gl2(xs: list): return len(xs)
    # gb.py
    import ga
    def run():
        f = ga.g;   print(f(4))        # 5   -- correct
        h = ga.gs;  print(h("a"))      # a!  -- correct
        k = ga.gl2; print(k([1,2,3]))  # SIGSEGV
    # d6.py
    import ga
    import gb
    gb.run()

So this is not only a return-convention gap: an unnormalised def also reads its
ARGUMENTS through the wrong convention, and a class-typed parameter crashes.

## Why a wider scan is the wrong fix

The scan cannot be widened to cover tokens that do not exist yet. A module is
lexed when its import is REACHED, so the reads that matter may be lexed after the
def is compiled, and no amount of scanning fixes an ordering. Nor may the
normalisation be made unconditional: that is
`bug-nilpy-import-name-forces-function-object-abi`, which is recorded as fatal for
a `Callable[...]` parameter.

## The shape of the answer

Put the RETURN KIND on the signature record and marshal in the bridge, the way
`PyHostCall` already does for a method (`rk := mi^.RetKind`, then a thunk chosen
by the RESULT with every argument one register wide, and `PXXObjRetain` on a
class result). `TPySigRec` is `{Code, ReqN, TotN, Star, Dflts, Names}` and
`TPyBoundRec` carries only `IsFunc: Boolean`, so today the pair bridge has no way
to ask. `PYSIG_SIZE` is 48 with fields at 0/8/16/24/32/40 — a RetKind at +48
(size 56) and a ParamKinds pointer beside it is the mechanical part; the
dispatch is PyHostCall's `ptrFamily` loop, which is exactly what
`bug-n-a-star-unpack-through-a-callable-value-stops-at-four-arguments` already
names as its own non-ladder answer. **One trampoline closes both tickets and
this one**, which is the argument for building it rather than widening anything
again.
