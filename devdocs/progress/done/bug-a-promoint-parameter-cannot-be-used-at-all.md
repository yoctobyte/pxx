---
track: A
prio: 45
type: bug
summary: "A PromoInt PARAMETER is unusable — @n, Pointer(n) and even `n + 0` are wrong or SEGFAULT — because promo was never joined to the aggregate-by-value parameter path every record already uses. Root cause and fix both confirmed by IR; no semantics decision needed."
status: done
owner: claude-AN
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

## The decision it needed — RESOLVED by measurement, 2026-08-04

This ticket first said the fix needs an ABI/semantics choice between
const-by-reference, copy-on-entry, and slot-by-value. **That framing was wrong.**
This compiler already has a settled convention for passing an AGGREGATE by
value, and a `PromoInt` (TypeSize 16 = {tag, payload}) is an aggregate. Measured
on a plain record:

```
caller:  8: lea       temp            { a hidden temp }
        10: copy_rec  temp, v, 16     { copy INTO it }
        11: arg       temp            { pass its ADDRESS }
callee:  0: lea       r               { resolves to the PASSED POINTER }
```

and behaviourally:

```
caller @v  = 140727563660480
callee @r  = 140727563660456     { the temp, NOT v }
after the callee does r.a := 99, caller's v.a is still 1
```

So the convention is: **caller copies into a hidden temp and passes its address;
`lea` of the parameter in the callee resolves to that pointer.** That already
gives true Pascal value semantics, with one copy, over an address-passing ABI —
no register-pair aggregate ABI anywhere, and nothing to decide.

A promo parameter is simply NOT in that class today. The caller already passes an
address (`slotaddr v`) — it just passes the ORIGINAL slot rather than a copy —
and the callee's `lea n` does not resolve to the passed pointer, so it addresses
an unfilled 16-byte frame cell. The two ends disagree only because promo was
never joined to the aggregate path.

### The fix

1. Put `PromoInt` in the aggregate-parameter class, so `lea n` in the callee
   resolves to the passed pointer exactly as it does for a record.
2. Have the caller materialise a hidden promo temp and copy into it before
   passing its address — with **`PXXPromoCopy`, not `copy_rec`**: the heap tier's
   payload is a managed AnsiString and needs the retain (`dp^ := sp^`), which a
   raw 16-byte byte-copy does not do. Check whether the by-value path for a
   RECORD CONTAINING a managed field already solves this; if it does, reuse it.
3. The temp needs the usual epilogue clear, the same as every other hidden
   managed temp (cf. `SymIsHiddenArgTemp` in `IRPromoBoxedVariantAddr`).

Value semantics fall out; there is no aliasing question, so no Track U item.
The earlier "const-by-reference" and "copy-on-entry" options are both worse
versions of this, and "slot-by-value (push two words)" would have invented a
register-pair aggregate ABI this compiler does not have and does not need.

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

## FIXED 2026-08-04

Exactly the shape the corrected analysis predicted, in three small pieces plus a
consistency fix. No new ABI, no semantics decision.

1. **`PromoInt` joins the by-ref aggregate class** (`parser.inc`, the same arm
   that promotes a record larger than a qword). The callee's `lea n` then
   resolves to the passed pointer, as it already did for records.
2. **`IRPromoAddrOf` resolves through a by-ref promo symbol** — `IR_LEA` instead
   of `IR_SLOTADDR` when `Syms[i].IsRef`. `IR_SLOTADDR` hands back the address OF
   THE CELL, i.e. a pointer to a pointer.
3. **The caller copies into a hidden temp** (`IRLowerCallArg`), with
   **`PXXPromoCopy`, not `copy_rec`**: the heap tier's payload is a managed
   AnsiString and the copy must RETAIN it (`dp^ := sp^`), or the callee's
   epilogue releases a string the caller still owns. This is what makes it VALUE
   semantics; without it the callee wrote straight through and `n := n + 1`
   changed the caller's variable.
4. **`Pointer(n)` now means `@n` for a promo operand.** It worked for a LOCAL,
   whose rvalue already is its slot address, and crashed for a by-ref PARAMETER,
   whose cell holds the address instead — one spelling, two meanings, with a
   segfault on the side that had worked a line earlier.

Two things surfaced while fixing it that the ticket had wrong:

- **The promo STORE path excluded `IsRef` outright.** Harmless while promo
  parameters did not work at all; once they did, `n := n + 1` fell through to a
  path that silently DROPPED the write. Fixed with the same LEA-vs-SLOTADDR rule.
- **The `viaOp` repro conflated two bugs.** `function viaOp(n: PromoInt):
  PromoInt` mixes a promo parameter with a promo RESULT. The addition was never
  the problem; a function RETURNING PromoInt crashes with no parameter involved,
  on `pinned` too. Filed as [[bug-a-promoint-function-result-crashes]] — which is
  why this ticket's headline "even `n + 0` SEGFAULTS" overstated the parameter
  half.

### Verified

The motivating case works — base conversion written in ORDINARY Pascal against
`PromoInt`, which needs a promo parameter, `shr`, a machine-int cast and
mutation of the parameter at once:

```pascal
function toHex(n: PromoInt): AnsiString;
begin
  while n <> 0 do
  begin
    d := Integer(n and 15);
    Result := digits[d + 1] + Result;
    n := n shr 4;
  end;
end;
```

`toHex(2**70)` = `400000000000000000`, agreeing with the runtime's own
`PXXPromoToBase(@v, 16)`.

`test/test_promoint_parameter.pas` covers both tiers, read/operate/chain/mutate,
the caller staying unchanged after a callee mutation, both `@n` and `Pointer(n)`,
and the library function.

### Gate

`tools/gate.sh quick` + **`make test`** green. The full Pascal suite was run
deliberately: this changes the shared parameter-registration path, so the risk
is every aggregate parameter in the codebase, not just promo ones. Nothing moved.

## Log
- 2026-08-04 — resolved, commit 7e5ea47c5.
