---
type: bug
track: A
prio: 5
summary: a COMPUTED string inside an `array of const` literal is never released — 937 per 1000 trips bare, 989 through Format, 900 for a function result; a named variable or a plain literal in the same position is clean. Survives 88e1ab536, so it is a third site in that family, not the same one
tags: [memory-leak, array-of-const, format, temporaries]
---

## Measured

1000 trips, `-dPXX_ALLOC_CENSUS`, on `8e853c4cba34` (HEAD `49f626c7c`, which
CONTAINS `88e1ab536`). Rebuilt to `converged` before measuring, because the
first run of these rows was on a binary that predated that fix and the whole
point is whether it survives it.

    shape                                          live   allocs
    TakeC(['lit' + Chr(c), i])                      937    1871   LEAK
    Format('%s-%d', ['lit' + Chr(c), i])            989    9755   LEAK
    Format('%s-%d', [IntToStr(i * 100000), i])      900    9755   LEAK
    ---- clean, same allocs, so all of these reached the heap ----
    TakeC([t, i])           t a named AnsiString      3    1871
    TakeC(['plain literal', i])                       2     921
    Format('%s-%d', [t, i]) t a named AnsiString      3    9755

`TakeC` is `procedure TakeC(const a: array of const)`. About one block per call.

The clean rows are the controls that make this a finding: the SAME allocation
count with a named variable in the same argument position is released correctly,
so the `array of const` marshalling is not broken in general — only for an
operand that arrives as a temporary nobody owns.

## It is not 88e1ab536, and not the sites that fixed

Same SHAPE as the Variant string-temporary family (a value arrives with a +1
belonging to nobody and no owning temp is parked for it), but a different site:
no Variant is involved anywhere in these rows. `88e1ab536` fixed the
Variant→AnsiString conversion seam in `IRLowerVariantAsScalar` and the
variant-BOXING site behind `v = <computed>`; both are variant-specific and
neither is on this path. Verified by measuring after that commit is in the tree,
not by reading its diff.

Nor is it the managed-string ARGUMENT temp mechanism: that one works. A computed
string passed to a plain `const AnsiString` parameter is clean (measured live=1,
and a call-result string temp in the same position is also clean), because the
seven arg sites park it in a hidden owning temp. An `array of const` element
goes through a different marshalling path that has no such parking.

## Why it matters more than the count suggests

`Format('%s', [something computed])` is the single most ordinary line of Pascal
there is. Every call leaks its argument. The row above is only 1 block per call
because the probe passes one string; a Format with three computed arguments
leaks three.

## Where to look

The `array of const` / `TVarRec` element marshalling, wherever an element of
`vtAnsiString` kind takes the operand's value. It needs the same treatment the
argument path already has — park a non-owned operand in a hidden temp so scope
exit releases it — and per the lesson from the seven arg sites, aim at whatever
predicate decides "this operand is already owned" rather than at one call site.

**Do not copy the arg sites' AST-shape test.** That predicate asks whether the
argument node is `AN_IDENT`/`AN_FIELD`/`AN_INDEX`/`AN_DEREF`, and the bug fixed
in `88e1ab536` was precisely that the shape stops describing what the lowering
produced. Ask what the lowering emitted, not what the source looked like.
