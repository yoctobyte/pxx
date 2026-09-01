---
type: bug
track: A
prio: 4
summary: a Variant converted to AnsiString leaks the result whenever it is a TEMPORARY — a const-AnsiString argument (921/1000) or a comparison against a computed string (936/1000); the dyn array and the SetLength churn in the old title were never ingredients, a plain local Variant leaks identically
tags: [memory-leak, variant, ansistring, temporaries]
status: working
owner: frankA
---

Found while writing `test_record_variant_member_leaks`: the obvious spelling of
its assertion helper (`Chk(const got: AnsiString)` fed `a[1].v`) leaked, which
would have put an unrelated bug inside the bound of a leak test. That test
compares inline and says why, as does `test_managed_record_gate_leaks`.

## The boundary, re-measured 2026-09-01

**An earlier revision of this ticket had the boundary wrong**, and wrong in the
direction that costs the most: it named two ingredients (a dyn array, and
SetLength churn) that are not ingredients at all, so anyone picking it up would
have gone looking inside the resize path. Neither is required. What is required
is that a Variant be converted to an AnsiString **and the result be a temporary
nobody owns**.

1000 trips each, `-O2 -dPXX_ALLOC_CENSUS`, live blocks at exit, no record and no
array anywhere in these rows:

    v = ('lit' + Chr(..))       Variant vs a COMPUTED string   live=936   LEAK
    Take(v), const AnsiString   Variant as a string ARGUMENT   live=921   LEAK
    v = s                       Variant vs a string VARIABLE   live=1     clean
    v = 'literal'               Variant vs a LITERAL           live=1     clean
    s := v                      Variant INTO a string variable live=1     clean
    v := 'lit' + Chr(..)        assignment alone               live=1     clean
    s = ('lit' + Chr(..))       string vs computed string      live=1     clean

The last two rows are the controls that make this a finding rather than a
coincidence: the same computed temporary compared against an **AnsiString** is
released correctly, so the temporary machinery works — it is the **Variant
boundary** that drops it. And `s := v` is clean, so a Variant→AnsiString
conversion is fine when its result lands in a variable that owns it.

**One block per conversion.** Three conversions per trip over 1000 trips gives
~2800 expected against 921 measured for a single-conversion row; the rows above
each do one conversion per trip and land at ~930.

## What the old rows actually showed

Re-measured on today's binary, the two shapes the old text called decisive:

    variant in a dyn-array record, WITH churn, read via param   live=921   LEAK
    the same, NO churn at all                                   live=967   LEAK
    the same churn, reading only the AnsiString member          live=7     clean

The no-churn row was recorded as `live=1` and is not; that single number is
where the false boundary came from. The third row still holds and is the useful
part — it says the leak follows the VARIANT read, not the resize.

## Not caused by anything landed since

Verified against the pinned stable compiler `stable_linux_amd64/default/stable_pinned`
(Aug 30, predating `b2997a31b`, `f806993c8` and the managed-record gate widening):
the plain-local row measures **live=921 there too**, identical. So this is
pre-existing and independent of the record-descriptor work, which is also why no
row here involves a record at all.

## Where to look

The conversion site that materialises an AnsiString from a Variant for a
non-owning destination — an argument slot or a comparison operand — and does not
register the temporary for release. `s := v` taking the owning path is the
contrast that should localise it.

## Root cause, found 2026-09-01 (frankB)

**The predicate asks about the AST SHAPE; the ownership question is about what
the LOWERING produced.**

`ir.inc` gives a managed-string argument an owning temp like this (7 sites, the
one at ~11862 shown):

    argIsManagedTemp :=
      (not isRefArg) and ParamWantsManagedStrTemp(cpi, pathIdx) and
      (ASTKind[ASTLeft[item]] <> AN_IDENT) and
      (ASTKind[ASTLeft[item]] <> AN_FIELD) and
      (ASTKind[ASTLeft[item]] <> AN_INDEX) and
      (ASTKind[ASTLeft[item]] <> AN_DEREF);

When true it allocates a hidden `tyAnsiString` var, stores the value into it and
passes that, so scope exit releases it. The four exclusions say "this argument
is a place somebody else already owns, so no temp is needed."

For `Take(v)` where `v: Variant` and the parameter is `const AnsiString`, the
argument node IS an `AN_IDENT`, so the exclusion fires and no owning temp is
made. But the value passed is not `v`: `IRLowerCallArg` has routed through
`IRLowerVariantAsScalar` (ir.inc ~6215), which ends at

    IRLowerVariantAsScalar := IRAppendCall(vuProc, vuArg, -1, Ord(vuRet));

calling `VariantToStrPas` and returning a BRAND-NEW AnsiString with a refcount
nobody holds. The AST still looks like a plain variable. The same applies to
`a[1].v` (AN_INDEX / AN_FIELD), which is why the dyn-array-record spelling leaks
identically — and why the old "needs SetLength churn" reading looked plausible.

Confirmed by IR dump (`PXXDBG=a.ir:Leaky`) — node 13 is the conversion call
returning tk=23 (AnsiString), node 14 passes it, and nothing releases it:

    11: lea      [sym=v]
    12: arg      a=11  tk=22
    13: call     a=156 b=12  tk=23     <- fresh AnsiString, unowned
    14: arg      a=13  tk=22
    15: call     a=248 b=14            <- Take

**The temp machinery itself is not broken**, which is what makes this narrow.
Measured, 1000 trips: a binop string temp as an argument, a CALL-RESULT string
temp as an argument, a call-result temp as a comparison operand, and a
call-result temp assigned to a variable are all clean (live=1). Only the Variant
coercion leaks (921). So every other producer of an unowned AnsiString is
registered; this one seam is not.

**Fix shape, and the trap in it.** The predicate needs to be true when the
argument is a Variant being coerced to AnsiString, regardless of AST kind. The
trap is that the same predicate-plus-four-exclusions is spelled out at SEVEN
sites (~11862, 12107, 12346, 12545, 12666, 13806, 13923) — the comment at 12346
calls itself "THE SEVENTH SITE" — so adding a clause in one place fixes one
spelling and leaves six. The right change is one helper taking the arg AST that
answers "does this argument need an owning temp", replacing the repeated
predicate at all seven, per normalise-dont-special-case.
