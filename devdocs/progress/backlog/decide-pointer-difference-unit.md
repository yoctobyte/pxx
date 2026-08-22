---
track: U
prio: 30
type: decision
blocked-by: []
status: backlog
summary: "FPC's `p - q` answers BYTES when either operand is an untyped Pointer (which includes `@x` under the default {$TYPEDADDRESS OFF}) and ELEMENTS when both are the same typed pointer. pxx always answers elements. `p - @a[0]` therefore prints 8 in FPC and 2 in pxx — a silent difference in ported code. Match FPC, keep the uniform rule, or diagnose?"
---

# Should `p - <untyped pointer>` count bytes, as FPC does?

Raised 2026-08-22 while fixing `bug-p-pointer-difference-is-typed-as-a-pointer`.
This is a dialect choice, not a defect, so it is a decision rather than a fix.

## The fork

```pascal
var a: array[0..7] of Integer; p, p0: ^Integer; u: Pointer;
p0 := @a[0]; p := @a[2]; u := @a[0];
```

| expression | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `p - p0` (both typed `^Integer`) | 2 | 2 |
| `p - TPI(u)` (cast back to the typed pointer) | 2 | 2 |
| `p - u` (untyped `Pointer`) | **8** | **2** |
| `p - @a[0]` (`@` is untyped under FPC's default) | **8** | **2** |

FPC's rule is a consequence of `{$TYPEDADDRESS OFF}` being its default: `@x` has
type `Pointer`, and a difference involving an untyped pointer has no element to
count, so it counts bytes. pxx scales by the LEFT operand's stride whatever the
right operand is.

## Options

1. **Match FPC.** Use the *smaller* of the two operands' strides, so an untyped
   operand (stride 1) forces a byte count. Cost: `p - @a[0]` — a natural way to
   write "index of p within a" — silently changes meaning for anyone who
   currently relies on pxx's answer, and `@` is the common spelling. Benefit:
   FPC-ported code computes the same number.
2. **Keep the uniform element rule** and record the divergence in
   `devdocs/dev/pascal-dialect-divergences.md`. pxx's rule is the more
   consistent one and matches C's typed-pointer semantics; the FPC behaviour is
   a legacy artefact of untyped `@` rather than a designed rule.
3. **Diagnose it.** Refuse `typed - untyped` with "cast the untyped operand to
   the pointer type, or to PtrUInt for a byte count" — neither dialect's answer,
   but nobody gets a silently different number. Optionally allow it under
   `--strict-fpc` with FPC's byte semantics.

## Recommendation

**Option 2, plus option 3's diagnostic behind `--strict-fpc`.** The uniform rule
is easier to explain and impossible to get subtly wrong; the FPC-parity answer
belongs with the other opt-in strictness rather than in the default dialect. But
this is exactly the kind of call CLAUDE.md says to escalate rather than pick.

## What is NOT in question

`p - q` over two pointers of the SAME typed pointer type counts elements in both
compilers, and that already agrees. The crash that led here (the difference node
typed as a pointer) is fixed and gated.
