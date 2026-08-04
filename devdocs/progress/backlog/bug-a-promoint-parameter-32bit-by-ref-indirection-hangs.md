---
track: A
prio: 40
type: bug
summary: "On 32-bit targets a PromoInt parameter still does not work: it does not compile today, and simply extending the 64-bit by-ref fix makes it HANG — the by-ref indirection is not resolved, so PromoShiftCount reads a garbage tag and `n shr 4` spins in BShr's doubling loop"
---

# A `PromoInt` parameter on a 32-bit target

The 64-bit half is fixed and verified
([[bug-a-promoint-parameter-cannot-be-used-at-all]]): a `PromoInt` parameter
joins the by-ref aggregate class, the caller copies into a hidden temp with
`PXXPromoCopy`, and the callee's `lea n` resolves through the cell.

That fix is deliberately restricted to **`tyPromoInt64`**, not `TypeIsPromoInt`.
On a 32-bit target `PromoInt` is the 8-byte `tyPromoInt32`, and extending the
same arm there does NOT work.

## Measured (i386, cross-compiled and run on x86-64)

With the arm extended to both kinds:

```pascal
function step(n: PromoInt): AnsiString;
begin
  n := n shr 4;
  Result := PXXPromoToStr(@n);
end;
```

**hangs** — killed at a 10s timeout, no output. Reads, `+`, `*`, chaining and
mutation of a promo parameter are all CORRECT on i386; only the operators with
no `PromoMixedHelper` form (`shr`, `and`, `div`, `mod` — the ones that box their
right operand into a promo temp) hang.

Consistent with the by-ref indirection not being resolved on that backend: the
runtime then reads the cell ADDRESS as a tag word, `PromoShiftCount` returns a
huge count, and `BShr`'s `for i := 1 to k do p2 := BMulSmall(p2, 2)` runs
essentially forever.

Restricted to `tyPromoInt64`, i386 returns to exactly its previous behaviour: a
promo parameter does not compile at all (same on `pinned`). That is a worse
feature but a better failure — a hang eats a suite timeout slot and reads as
infrastructure trouble, while the compile error is loud and local.

## Where to look

Whether `IR_LEA` on an `IsRef` parameter symbol resolves through the cell in
`ir_codegen_i386.inc` the way it does on x86-64. Check the record path first:
a record larger than a qword is already `IsRef` on 32-bit, so either that path
works there and promo differs for another reason, or records have the same gap
and nobody has hit it. **Measure it** — write a 32-bit test passing a large
record by value and mutating a field, before touching the backend.

Then verify on arm32 and riscv32 as well, not only i386; they are separate
backends with separate by-ref handling.

## Note on scope

Nothing needs this today: NilPy never uses a promo parameter (its promo values
cross call boundaries boxed as variants), and 32-bit is not where big-integer
Pascal code runs. It matters for the same reason the 64-bit half did — a
first-class type you cannot write a function against is a hole — just with far
less urgency, hence prio 40.

## Gate

`make test` + self-host byte-identical, plus the existing
`test/test_promoint_parameter.pas` cross-compiled and RUN for i386 (and arm32 /
riscv32 under their emulators), with a timeout so a regression to the hang shows
as a failure rather than a stall.
