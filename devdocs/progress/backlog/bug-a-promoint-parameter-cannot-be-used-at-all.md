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

## Likely shape

A promo rvalue is the slot ADDRESS ([[decide-promoint-rvalue-representation]]).
At a call site the argument therefore lowers to an address, and the callee's
parameter CELL holds that address — so inside the routine, `@n` is the address
*of the cell* (one level too many) and `IRPromoAddrOf`'s `IR_SLOTADDR` of the
parameter symbol is likewise wrong. Confirm before acting: dump the call site
and callee IR rather than trusting this paragraph
([[project_debug_toolkit_playbook]]).

If that is right, the lowering fix is small — `IRPromoAddrOf` emits
`IR_LOAD_SYM` instead of `IR_SLOTADDR` when the symbol is a promo PARAMETER.

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
   Most Pascal-faithful, but changes the parameter ABI for the type.

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
