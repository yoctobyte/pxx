---
slug: refactor-a-two-predicates-answer-what-a-caret-yields
title: "`NodePtrElem` and `ResolveDerefShape` both answer 'what does `^` yield', and neither is a superset"
track: A
prio: 55
type: refactor
blocked-by: []
status: done
owner: frankA
created: 2026-08-25
summary: "Two functions type a dereference. NodePtrElem knows more SPELLINGS (index-into-base, pointer FIELD, inline PTR_CAST, pointer arithmetic); ResolveDerefShape knows more ABOUT each (remaining depth, ultimate base). Swapping a call site from one to the other trades one kind of knowledge for the other, silently — which is exactly what shipped a regression on 2026-08-25."
---

# The two

| | file | knows |
| --- | --- | --- |
| `NodePtrElem(node, var elemTk, var elemRec, depth)` | `pasparser_lval.inc` (this ticket said `symtab.inc`; it is not there and a resolver looking for it will not find it) | the IMMEDIATE pointee, over many node shapes: `AN_IDENT`, `AN_INDEX` (recursing into its base), `AN_FIELD`, `AN_PTR_CAST`, and `AN_BINOP` pointer arithmetic |
| `ResolveDerefShape(node, var tk, var recName, var remDepth, var ptrBaseTk, var ptrBaseRec)` | `pasparser_lval.inc` | the pointee **plus remaining depth and ultimate base**, over `AN_IDENT`, `AN_FIELD`, `AN_INDEX` *(AN_IDENT base only)*, `AN_DEREF`, the call kinds, `AN_PTR_CAST`, and a final else that delegates to `NodePtrElem` |

Neither contains the other. `ResolveDerefShape` is richer per shape and poorer
in shapes.

# What that cost, concretely

`15ec54d7a` moved the alias-cast suffix walk in `pasparser_expr.inc` off
`NodePtrElem` and onto `ResolveDerefShape`, to fix `PPRec(pp)^^.f` resolving
every trailing field at offset 0 — a real fix, and depth is exactly what
`NodePtrElem` cannot give.

It also broke `PRec(raw)^.arr[1]^`, which had been fine: an `AN_INDEX` whose
base is an `AN_FIELD` (a `array[0..2] of PStr` field). `ResolveDerefShape`'s
index arm handles only an `AN_IDENT` base, so it claimed the node, answered
`tyUnknown`, and the walk fell back to the OUTER cast's alias. The test printed
a raw pointer where it had printed `world`
(`regression-test-core-test-cast-deref-chain-siblings`, fixed in `bfb7b4c59` by
having `ResolveDerefShape` ask `NodePtrElem` whenever its own arms came out
`tyUnknown`).

That patch stops the bleeding. It does not stop the next swap.

# Shape of the fix

One function that answers the full triple for every spelling. The cheapest
honest route is to lift `NodePtrElem`'s missing shapes INTO `ResolveDerefShape`
— an `AN_INDEX` over a non-IDENT base, and pointer arithmetic — with the depth
metadata each of them can actually supply, then make `NodePtrElem` a thin
wrapper that discards the depth for the callers that only want the pointee.
Beware: the array-element depth lives in the ARRAY symbol's own
`SymPtrDepth`/`SymPtrBaseTk` slots (see the long note in `ResolveDerefShape`'s
index arm), and a FIELD's in `UFldPtrDepth`/`UFldPtrBase*`; a non-IDENT base has
no such row, which is why that arm gave up in the first place. Widening it may
mean answering "pointee known, depth unknown" explicitly rather than pretending
depth 0.

# Same disease, one type family over

[[refactor-a-two-dyn-array-depth-functions-that-drift]] — `NodeDynDepth` vs
`DynArrayNodeDepth`, same week, same failure mode (a silent wrong VALUE, not an
error). `devdocs/dev/normalise-dont-special-case.md` is the doctrine; here the
double case is two whole functions rather than two arms.

# Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Pinned
by `test/test_cast_deref_chain_siblings.pas`,
`test/test_cast_deref_pointer_field.pas`,
`test/test_pointer_to_a_pointer_through_a_cast_and_a_forward.pas`, and the
`^PChar` shape tests. A full-tier A/B is worth asking Track T for, for the same
reason as the sibling ticket: the failure mode is a wrong value, not a red.

---

# Resolution — `ResolveDerefShape` is now a superset in shapes; `NodePtrElem` still exists

**Done, 2026-08-30 by frankA.** Fixedpoint `df1f8c66fca7` (2 rounds),
`tools/gate.sh quick` GREEN.

## What changed — `compiler/pasparser_lval.inc`, three edits

1. `ResolveDerefShape` became a thin public wrapper over a depth-carrying
   `ResolveDerefShapeAt(..., depth)`. The bound (8) is the same one
   `NodePtrElem` has always had, and it exists because the two new arms recurse
   into a **sub-expression** rather than into a symbol row.
2. **`AN_INDEX` over a non-IDENT base** — previously answered `tyUnknown` and
   fell through to the `NodePtrElem` backstop, which got the pointee right and
   dropped the depth. It now recurses into the base **with this walk**, so the
   base's own arm supplies the depth and ultimate base it always could.
3. **`AN_BINOP` `tkPlus` / `tkMinus`** — pointer arithmetic, a shape this walk
   had no arm for at all. It recurses into whichever operand answers.

## Measured — the widening has teeth, and it is not cosmetic

Five shapes, new binary `df1f8c66fca7` against pinned `992065f21f33`:

```
        shape                            pinned      new
  1  (ip + 1)^        ^Integer            30         30      control
  2  (bp + 1)^        ^Byte                4          4      control
  3  (pp + 1)^        ^PChar         4419456       beta      FIXED
  4  r.q[1]^          index / IDENT base    beta       beta      control
  5  PRec2(raw2)^.q[1]^  index / FIELD base 4419456     beta      FIXED
```

Rows 3 and 5 are **silent wrong values on the pinned binary** — a raw address
printed where a string belongs — so this refactor closed two live defects that
nobody had filed. Rows 1 and 2 are the controls that matter most: pointer
arithmetic on `^Integer` and `^Byte` is span-scaled, so a wrong pointee there
would move the number, and it does not.

Also SAME as pinned: the three tests this ticket pins, plus
`test_cast_lvalue_suffix_siblings`, `test_ptr_depth2_bases`,
`test_pchar_paren_deref_and_copy`, `test_pointer_param_keeps_its_depth`,
`test_pointer_deref_depth`.

Rows 3 and 5 are now `test/test_deref_shape_through_arith_and_nonident_base.pas`
in `test-core`, and it **fails on the pinned binary** — checked, because a test
written after a fix that passes on the broken binary is testing nothing.

## What was NOT done, and why — `NodePtrElem` is not a wrapper

The ticket's stated end state is "make `NodePtrElem` a thin wrapper that
discards the depth". That is **not** what landed.

**One of this ticket's own premises does not survive checking.** It reads as
though `NodePtrElem` has call sites to protect. It has none:
`grep -rn NodePtrElem compiler/` finds the definition, its own recursion, two
calls inside `ResolveDerefShape` (the final else and the `bfb7b4c59` backstop),
and otherwise only prose. `15ec54d7a` moved the last external caller away, which
is the very swap this ticket was filed about — so the collapse is smaller than
the ticket assumes, and its risk is not "every caller" but the two fallbacks.

What actually blocks it:

- **It is circular today.** Both remaining calls are *inside* the walk.
  `NodePtrElem` calling back into `ResolveDerefShape` closes a loop that has to
  be broken by hand first.
- **The contracts differ at the failure edge.** `NodePtrElem` returns `False`
  for a node it cannot type; `ResolveDerefShape`'s final else answers
  `tyInteger`. The `False` is load-bearing at both fallbacks.

**But the ticket's harm is gone, which is why this closes rather than parks.**
The danger was that swapping a call site *traded* knowledge. It no longer does:
`ResolveDerefShape` now covers every shape `NodePtrElem` does (IDENT, INDEX
including a non-IDENT base, FIELD, PTR_CAST, BINOP +/-) and is richer on each,
so a swap **towards** it is safe — which is precisely what `15ec54d7a` was not.

## Are the fallbacks still reached? Measured, with a control

A counter on the final else, on the `tyUnknown` backstop, and on each new arm;
built twice, once with the new arms live and once with both disabled
(`depth < 8` → `depth < 0`), so the zeros can be read:

```
                                              arms ON              arms OFF
  file                              calls  idx arith else back   idx arith else back
  test_deref_..._nonident_base.pas    506    1    3    0    0      0   0    3    1
  test_cast_deref_chain_siblings.pas  315    1    0    0    0      0   0    0    1
  compiler/compiler.pas               436    0    0    0    0      0   0    0    0
  test_ptr_depth2_bases.pas           435    0    0    0    0      0   0    0    0
```

Read the middle column first: **the new arms take exactly the four hits the
fallbacks used to take**, one for one, in both files where anything fires. The
`backstop=1` on `test_cast_deref_chain_siblings` is the shape `bfb7b4c59` added
the backstop *for*; the new index arm now serves it, with the depth the backstop
could not supply.

**The zeros are not vacuous** — that is what the arms-OFF column is for; the same
counters fire there. Two honest limits: `compiler.pas` reads 0 in **both**
columns, so its 436 calls are evidence about neither fallback, and the
population is six files, not a suite. That is why nothing was deleted.

Follow-up: [[refactor-a-collapse-nodeptrelem-into-the-deref-walk]].

## Log
- 2026-08-30 — resolved, commit 72b4bd51a.
