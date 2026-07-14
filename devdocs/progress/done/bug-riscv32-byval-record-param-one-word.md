---
prio: 50
---

# riscv32: a BY-VALUE record parameter wider than 4 bytes passes only its first word — SILENTLY

- **Type:** bug (riscv32 backend — call ABI)
- **Track:** A — core (riscv32 backend, possibly parser gate)
- **Found:** 2026-07-14 while closing [[bug-riscv32-p256field-coredump]] (b356).

## Repro (8-byte unmanaged record; the managed case crashes instead)

```pascal
program bg10;
type TR = record n1: Integer; n2: Integer; end;
function F(x: TR): Integer;
begin
  F := x.n1 * 1000 + x.n2;
end;
var a: TR;
begin
  a.n1 := 7; a.n2 := 9;
  writeln('f=', F(a));    { x86-64: 7009.  riscv32: 7000 — x.n2 read as 0. }
end.
```

A managed record (`TBigInt`: Boolean + dynarray) passed by value SEGFAULTS in
the callee instead (the handle word never arrives). This is why
`lib_bignum_ops` still diverges then dies on riscv32 after b356 — bignum's
operator layer takes `(a, b: TBigInt)` **by value**.

## What is actually wrong

The riscv32 call-argument loop has no record branch at all: a by-value record
argument falls to the generic ONE-WORD case. arm32 passes 5–8-byte records as
two words (b-numbered fix in tree: `bug-arm32-record-byvalue-over-4-bytes-abi-gap`);
i386 REJECTS at compile time (`only ordinal/pointer parameters supported yet`,
parser gate near `parser.inc:20795`). riscv32 does neither — it silently
truncates, the worst of the three behaviors.

Note the asymmetry that hid this: the same record passed through an OPERATOR
overload (`operator * (const x, y: TR)`) works — that path materialises temps
and passes addresses — so bg6/bg7-style probes pass while direct calls with
by-value params miscompile.

## Wanted (either order)

1. Short-term: riscv32 rejects >4-byte by-value record params at compile time
   like i386 — a loud error instead of silent word-1 truncation.
2. Real fix: pass them properly (two words for 5–8 bytes mirroring arm32, and
   pointer-to-copy for larger/managed ones — which is also what bignum needs,
   since `TBigInt` is 12+ bytes and managed).

Acceptance: bg10 prints 7009 on riscv32; `lib_bignum_ops` runs green on
riscv32 with output identical to x86-64 (it is green on x86-64/aarch64/arm32).

## Log
- 2026-07-14 — resolved, commit f6c6780e.
