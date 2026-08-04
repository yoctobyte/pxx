---
track: A
prio: 45
type: bug
summary: "A PromoInt PARAMETER is unusable: @n and Pointer(n) both yield a pointer to the parameter CELL rather than the slot, and even `n + 0` on the parameter SEGFAULTS — so PromoInt is a type you can compute with but cannot write a function against"
---

# A `PromoInt` parameter cannot be used at all

Split out of
[[bug-a-promoint-shr-yields-nothing-and-a-machine-int-cast-yields-the-slot-address]],
whose other two defects (`shr`, and the machine-int value casts) are fixed. This
third one is left open on purpose: it needs an **ABI/semantics decision**, not
just a lowering fix.

## Measured (2026-08-04, at HEAD with the other two fixed)

```pascal
program t;
uses promocore;
function viaAt(n: PromoInt): AnsiString;  begin Result := PXXPromoToStr(@n); end;
function viaPtr(n: PromoInt): AnsiString; begin Result := PXXPromoToStr(Pointer(n)); end;
function viaOp(n: PromoInt): PromoInt;    begin Result := n + 0; end;
var v: PromoInt;
begin
  v := 1; v := v * 70000000000;
  writeln(viaAt(v));    { 4348384 — a pointer }
  writeln(viaPtr(v));   { 4348384 — a pointer }
  writeln(viaOp(v));    { SEGFAULT }
end.
```

The same expressions on a program-scope LOCAL are all correct, so this is
specifically the parameter path.

**`viaOp` is new information** — the original ticket recorded only that `@n` and
`Pointer(n)` give pointers, i.e. that you cannot reach the runtime by hand. It
is worse than that: **an ordinary promo OPERATOR applied to a parameter
crashes**, so a promo parameter cannot be used even through the operators the
frontend lowers for you.

## CONFIRMED by IR on both sides (2026-08-04)

Not a hypothesis — measured with `PXXDBG=a.ir` at each end.

**Caller** (`writeln(callee(v))` with `v: PromoInt`):

```
5: slotaddr a=81            { &v }
6: arg      a=5   tk=28     { passed as ONE machine word, tk 28 = tyPromoInt64 }
7: call     a=251
```

**Callee** (`PXXPromoToStr(@n)`):

```
0: lea a=82 [sym=n]         { the address OF THE PARAMETER CELL }
1: arg a=0
2: call a=184
```

So the caller passes **the slot address**, and the callee takes **the address of
the cell that holds it** — one indirection too many, on every single promo
operation, because `IRPromoAddrOf` answers `IR_SLOTADDR` for any promo-typed
symbol without asking whether it is a local or a parameter.

That also explains `n + 0` crashing where `@n` merely printed a pointer:
`PXXPromoAddInt(&cell, ...)` reads the tag word at `&cell`, which holds the
caller's ADDRESS — neither `PROMO_TAG_INLINE` (0) nor `PROMO_TAG_HEAP` (1) — so
the runtime takes the heap branch and dereferences that address as a managed
`AnsiString` payload.

`Pointer(n)` and `@n` lower IDENTICALLY (both to `lea n`), which is why the
original ticket saw the same wrong number from both spellings and concluded a
parameter is "neither a slot nor an address". It is a slot by the CALLEE's
reckoning and an address by the CALLER's.

**The two ends already disagree about the convention.** The callee lowering was
written as though the slot lives in the callee's own frame (option 3 below); the
caller implements option 1. Either end alone is coherent; the pair is not. That
framing is what the fix has to choose between — the one-line `IRPromoAddrOf`
change (emit `IR_LOAD_SYM` for a promo PARAMETER) simply commits to the caller's
convention, which is option 1 and carries the aliasing question with it.

## The decision it needs first — Track U

Passing the caller's slot address makes a promo parameter **by reference**,
so a callee assigning to `n` would mutate the caller's variable. Pascal's
`value` parameter semantics say it must not. The options:

1. **Const-by-reference** (pass the address, forbid or ignore assignment to the
   parameter). Cheapest, matches how every other promo site already works, and
   is enough for the motivating use (library functions that only READ, e.g. a
   hand-written base conversion). Diverges from Pascal value semantics.
2. **Copy on entry** (pass the address, `PXXPromoCopy` into a fresh callee slot
   in the prologue). Correct Pascal semantics; costs an allocation per call for
   a heap-tier value, and needs the copy released in the epilogue.
3. **Pass the two-word slot by value** and treat the parameter as a real slot.
   Most Pascal-faithful, and note the CALLEE side is ALREADY written this way —
   only the caller would change (push two words instead of an address), and
   `IRPromoAddrOf` would need no change at all. The cost is a per-call copy of
   the managed payload with the same lifetime question as option 2, plus a
   parameter-ABI change for the type.

Recommendation: **2**, with 1 as an explicit `const PromoInt` fast path — a type
whose parameters silently alias would be a worse surprise than the cost, and
`const` already means "no assignment" in this dialect. Filing as a `decide-`
item is warranted if that is not obviously right.

## Not on the critical path

The NilPy side does not need this: `hex`/`bin`/`oct`/`str` over an
arbitrary-precision int are frontend lowerings to `PXXPromoToBase` /
`PXXPromoToStr`, which is the pattern for reaching the runtime and does not
involve a promo parameter. This matters for **Pascal source** writing a library
against `PromoInt`, which today is impossible.

## Gate

`make test` + self-host byte-identical, plus a Pascal test covering: a promo
parameter read, operated on, passed on to another routine, and (per whichever
option is chosen) assigned to — with a heap-tier value, not only an inline one.
