---
slug: bug-n-a-base-class-named-by-a-pascal-reserved-word-is-not-mapped
track: N
prio: 25
type: bug
status: done
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, reserved-words, qualifier, shim]
blocked-by: []
summary: "RESOLVED 2026-09-09. `class C(array.array):` was refused with `Nil Python: unknown base class array` while `class C(array.array_):` compiled: the qualified-member mapping PyMapReservedMember (`tk.END` -> END_) is applied at four sites and the BASE-CLASS position was the fifth, which never had it. Found by sweeping the siblings after fixing the CONSTRUCTOR site the same day -- same absence, but that one was SILENT (it built garbage) where this one REFUSES, which is why it sat unnoticed and why it was ranked 25 rather than 55. Fixed in the qualified arm of the base lookup, tried AFTER the plain spelling so it can only ADD a resolution, and gated on the qualifier so an unqualified base name is still the program's own. Covered by rows in test_nilpy_the_array_module.npy with an unqualified refusal control."
---

# A base class named by a Pascal reserved word is not mapped

## Repro (measured 2026-09-09, compiler 418064fca1d3)

```python
import array
class C(array.array):      # was: Nil Python: unknown base class array
    pass
class D(array.array_):     # compiled
    pass
```

## The five sites, so the next one is not missed either

`PyMapReservedMember` is applied at:

| site | position |
| --- | --- |
| `pyparser.inc` value/call, via `ConsumeUnitQualifier`'s NilPy caller | had it |
| `pasparser_expr.inc` expression | had it |
| `PyClassCreate` constructor name | added 2026-09-09 (was SILENT) |
| the gate routing a qualified construction there | added 2026-09-09 |
| **base class** | **added 2026-09-09 — this ticket** |

## Why a grep could not find this class of defect

frankH's framing, kept because it generalises: the constructor gap was not two
copies that DRIFTED — it was a site where the check had never been written.
**Nothing was wrong anywhere; something was absent, and absence collides with
nothing.** A grep for `PyMapReservedMember` returns the sites that are already
right and says nothing whatever about a missing one, so the usual
find-the-copies-and-compare sweep is blind to it.

**What worked was inverting the search: enumerate the positions the rule should
cover — every site that consumes a unit qualifier — and subtract the ones that
have it.** That is the reusable half.

## And the first attempt at the fix silently did nothing, which is the second lesson

The obvious edit is to map the name right after `ConsumeUnitQualifier` returns:

```pascal
baseQName := CurTok.SVal;
baseQUnit := ConsumeUnitQualifier(baseQName);
if baseQUnit >= 0 then baseQName := PyMapReservedMember(baseQName);   { does NOTHING }
```

It compiles, it is in the right place, and it changes no behaviour: the base
lookups below read **`CurTok.SVal`**, not `baseQName`. The variable the
qualifier consumer writes and the variable the resolver reads are different, and
the repro failed identically before and after. Caught only because the repro was
re-run rather than assumed to be fixed — a `make` and a rebuild are not evidence
that an edit did anything.

The fix is in the qualified arm of the lookup itself, after the plain spelling:

```pascal
baseCi := FindUClassInUnit(CurTok.SVal, baseQUnit);
if baseCi < 0 then
  baseCi := FindUClassInUnit(PyMapReservedMember(CurTok.SVal), baseQUnit);
```

Plain-spelling-first means a unit that really exports the bare name keeps it, so
this can only add a resolution and never redirect an existing one.

## Log

- 2026-09-09 — fixed and closed in the same change; the fix and its test row are
  in commit d1efd1dee (the base-class arm of `PyMapReservedMember`, plus the
  `class Grid(array.array)` rows in `test/test_nilpy_the_array_module.npy`).
