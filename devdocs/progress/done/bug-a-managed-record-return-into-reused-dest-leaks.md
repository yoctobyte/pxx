---
track: A
prio: 55
type: bug
---

# Managed-record function results into a REUSED destination leak the old payload

The final layer of [[bug-a-runtime-variant-heap-grows-unbounded]] (three other
layers fixed 2026-07-22). Generic repro, plain Pascal, x86-64 (ticket notes say
the shape grows on aarch64 too):

```pascal
type TR = record n: Integer; xs: array of Integer; end;
function mk(v: Integer): TR;
begin SetLength(Result.xs, 4); Result.n := v; end;
function add2(const a, b: TR): TR;
begin SetLength(Result.xs, 4); Result.n := a.n + b.n; end;
var r: TR; k: Integer;
begin
  for k := 1 to 200000 do
    r := add2(mk(k), mk(1));    { 23.4 MB peak — ~117 B leaked per iteration }
end.
```

One call per fresh frame is FLAT (prologue zero + epilogue cleanup cover it).
The leak needs the call site to RE-EXECUTE within one frame (a loop): the
callee's aggregate-return epilogue RAW-copies Result into the caller's hidden
dest temp / assignment target (x86-64 `rep movsb`, riscv32 PXXMemMove), so a
reused dest's previous dynarray/string handles are overwritten without
release — one orphan per managed field per call.

## Why it matters
promoint's whole bignum tier is built on TBig (record + dynarray limbs)
returned by value from nested helpers — every heap-tier promo BITWISE op leaks
~60-690 B (see the umbrella ticket's 5-line PromoInt64 repro), which is what
still makes uforth's empty DO LOOP grow without bound (its ANS boundary check
manufactures heap u64s each pass). Any user code with `r := f(...)` returning
a managed record in a loop leaks the same way.

## Fix shape (watch the alias trap)
Release the destination's managed fields before (or as part of) the aggregate
result copy-in — BUT `r := add2(r, x)` may alias dest and argument, so a
release BEFORE the call frees memory the callee still reads. Safe points:
- hidden arg/result TEMPS never alias: release-before-call is safe there;
- for a direct assignment target, either route through a temp +
  IR_COPY_REC_MANAGED (which already handles retain/release ordering), or
  release AFTER the callee returns, before the writeback copy (the epilogue
  copy happens in the CALLEE though — needs the dest's layout at that point).
Also check ProcAggregateDestSym paths on every backend (x86-64 rep movsb,
aarch64 EmitA64CopyBytes, arm32, riscv32/xtensa PXXMemMove).

## Gate
lk23-style repro flat; `d := m and 65535` / `or` heap-tier PromoInt64 loops
flat; uforth `: T 100000 0 DO LOOP ; T` RSS bounded; make test + self-host
byte-identical + cross for touched backends.

## Log
- 2026-07-22 — resolved, commit 86d9d3c3.
