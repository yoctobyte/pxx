---
summary: "NilPy: ordering two statically-typed lists compares their HEAP ADDRESSES, not their contents — `[9,9] < [1,1]` is True; no comparison helper is called at all"
type: bug
track: N
prio: 70
---

# List ordering on the static path compares heap addresses, not contents

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep; cause corrected
  the same day after dumping the IR (see "Correction" below — the first reading
  of this ticket was wrong).

## Measured (self-hosted binary at `596fce8d5`)

```python
a = [9, 9]
b = [1, 1]
print(a < b)     # CPython False   pxx True
print(a > b)     # CPython True    pxx False
```

`a` is allocated before `b`, so `a`'s handle is the lower address and every
ordering operator answers from that. **Contents are not consulted at all.**

## Correction — this is NOT an equal-elements boundary bug

This ticket was first filed as "`[1,2] < [1,2]` returns True, so the equality
boundary is inverted", with a guess that `<`/`>=` were derived by negating
`pylist_cmp`. **That was wrong**, and the wrongness matters because it would
have sent the fix to the wrong file.

Dumping the lowering (`PXXDBG=a.ir:f`) shows the comparison is a single raw
`binop` on the two class handles — `pylist_cmp` / `pycmp_v` are **never
called** from the compiler at all (`grep pylist_cmp compiler/*.inc` is empty;
they have callers only inside pylib's own sort/min/max).

So the cases that looked correct were **coincidence**: `[1,2] < [1,3]` and
`[1] < [1,0]` agree with CPython only because the left list happened to be
allocated first. The `[9,9] < [1,1]` case above breaks that coincidence and
shows the real behaviour. `test_nilpy_mixed_type_operands` asserts
`[1] < [1, 0]` and passes for exactly this accidental reason.

## Relationship to the static-vs-variant hole

Same root as [[bug-nilpy-static-typed-operands-skip-mixed-type-guard]]: when
both operand types are known at compile time, the binop lowers straight to
machine comparison and never reaches the `pyvar_*` runtime helpers where the
real semantics live. The difference is what SHOULD happen at the end:

- that ticket: the operand pair is invalid in Python → must raise `TypeError`.
- **this ticket: the operand pair is VALID** (list vs list is defined, and
  lexicographic) → must call the existing `pylist_cmp` and compare its result
  against 0.

So this one cannot be fixed by adding a type-clash raise; it needs the static
path to route list-vs-list ordering into `pylist_cmp`. Worth doing together
with that ticket, since both are "the static lowering skipped the semantics",
but they need different endings.

## Scope

Every ordering operator (`<`, `<=`, `>`, `>=`) on two statically-typed lists.
Check the same for tuples (same `TPyList` row) and `bytes`. Strings are
**correct** already (`"ab" < "ab"` → False, verified), so the string path does
consult contents and is a working model to follow.

`==`/`!=` on lists are correct — `pylist_eq` IS wired from `ir.inc` (:5714),
which is precisely the wiring the ordering operators are missing.

## Fix shape

Mirror the `pylist_eq` wiring at `compiler/ir.inc:5714`: for an ordering binop
whose operands are both TPyList, emit a call to `pylist_cmp` and compare the
returned `Int64` against 0 with the source operator. `pylist_cmp` already
returns -1/0/1 with correct lexicographic and prefix-length semantics, so this
is wiring, not new logic.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython that **defeats allocation order** — the content-vs-address cases above
(`[9,9] < [1,1]`), equal lists, prefix cases (`[1] < [1,0]`), and nested lists.
A test whose expected order coincides with allocation order proves nothing here;
that is what let this survive.

## FIXED 2026-08-01

`compiler/ir.inc`, immediately after the `pylist_eq` arm it mirrors: an ordering
binop (`<` `<=` `>` `>=`) whose operands are both TPyList now emits a call to
pylib's `pylist_cmp` and compares the returned `Int64` against 0 with the SOURCE
operator. Comparing against 0 with the original operator is what keeps all four
correct at equality, rather than special-casing the boundary.

No new logic in pylib: `pylist_cmp` already implemented the real rule (element
by element via `pycmp_v`, then the shorter sequence first) and returned -1/0/1 —
it simply had no caller in the compiler. That is the whole bug: `==`/`!=` were
wired to `pylist_eq` and ordering was never wired to `pylist_cmp`.

Guarded by `PyProgramMode`, so Pascal-side class comparison is untouched.
Tuples ride along for free — a tuple is the same `TPyList` row.

### Verification

`test/test_nilpy_list_ordering.npy`, byte-identical to CPython, and written so
every ordering case **defeats allocation order** — the list written (hence
allocated) first is the one that must sort last. Covers content order, the
equality boundary for all four operators, a common prefix, nested lists, and
that `==`/`!=` are unchanged.

That test design is the point: the previous behaviour passed
`test_nilpy_mixed_type_operands`' `[1] < [1, 0]` because content order and
address order coincided there. Any future test in this area must break the
coincidence or it proves nothing.

Gate: `tools/gate.sh quick` (test-nilpy, self-host fixedpoint byte-identical,
testmgr --tier quick).

### Still open elsewhere

Ordering a list against a NON-list (e.g. `[1,2] < 3`) is a type error in Python
and still silently computes here — that is
[[bug-nilpy-static-typed-operands-skip-mixed-type-guard]], a different ending
(raise) for the same static-lowering hole, and is NOT fixed by this change.
Strings were already correct. `bytes` ordering not verified either way.
