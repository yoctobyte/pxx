---
slug: bug-o-the-in-place-string-append-is-x86-64-only-so-every-other-backend-is-quadratic
track: A
prio: 85
type: bug
status: urgent
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "`s := s + x` is O(n) on x86-64 and O(n^2) on EVERY other backend. 20000 one-char appends cost 10 allocations on x86-64 and 19780 on i386, arm32, aarch64 and riscv32 alike -- one whole-string copy per append. The runtime half (PXXStrAppend, with its documented `want := need * 2` doubling) is target-independent and correct; the recogniser IRIsSelfStrAppend and its emitter EmitAnsiStrAppendToSym are hand-emitted x86-64 machine code in ir_codegen.inc, so no other backend ever calls it -- measured directly, zero grow events on i386. NOT a 32-bit bug: aarch64 is 64-bit and equally quadratic. It is FATAL on 32-bit only because the address space runs out first, which is the whole of bug-a-pxxalloc-does-not-check-the-mmap-return-so-oom-arrives-as-an-anonymous-segv -- that ticket's unexplained appetite is this."
---

# The in-place string append is x86-64 only, so every other backend is quadratic

## Repro — ten lines, no cross-target hosting needed

```pascal
program appendgrow;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 1 to 20000 do s := s + 'x';
  WriteLn(Length(s));
end.
```

`pascal26 --target=T -dPXX_ALLOC_CENSUS appendgrow.pas`, allocations at exit:

| target | allocs for 20000 appends | |
| --- | --- | --- |
| x86_64 | **10** | geometric |
| i386 | 19780 | one per append |
| arm32 | 19780 | one per append |
| aarch64 | 19780 | one per append |
| riscv32 | 19780 | one per append |

All four wrong targets produce the *identical* count, which is what says it is
one shared missing path and not four backend bugs. Every arm returns len=20000:
the answer is right, only the cost is wrong.

## Where

`compiler/ir_codegen.inc` is the x86-64 emitter. Both halves of the optimisation
live in it and nowhere else:

- `IRIsSelfStrAppend` (~3870) — recognises the `s := s + x` accumulation shape
- `EmitAnsiStrAppendToSym` (~3890) — emits the call, as raw x86-64 bytes
- the decision site at ~6116, inside the `tyAnsiString` arm of the store

The runtime half is fine and is shared: `PXXStrAppend` in
`compiler/builtin/builtinheap.pas` grows in place when the block is sole-owner,
APPENDABLE and has spare capacity, and otherwise allocates `want := need * 2` —
whose own comment says *"that doubling is the whole difference between O(n) and
O(n^2)"*. It is reached by `RegisterProc('PXXStrAppend', ...)` and is callable
by any backend. Nothing about it is target-specific.

**Measured, not inferred:** a temporary probe on the grow path printed one line
per call. x86-64 running the 40-append version: 2 grow events. i386: **zero** —
`PXXStrAppend` is never called there at all, so the append goes down the plain
concat path that builds a fresh exact-size block from both halves every time.
(Probe removed again; the general tool it needed, `-dPXX_ALLOC_BIG`, landed as
6c54e432b.)

## Why it matters more than a normal -O ticket

It is a **correctness-of-completion** failure on 32-bit, not just a slow path.
The 32-bit-hosted compiler building `compiler.pas` dies at ENOMEM, and this is
why: 5931 of its first 19780 allocations are above the top census bin and carry
4.4 GB, in a creeping series (+8, +24, +40 …) that never doubles, while the
same build on an x86-64 host shows the same buffers growing 41943064 ->
83886104, exactly 2x.

Host and target were separated by control: an **x86-64 host** building for
`--target=i386` and `--target=arm32` completes normally (20.6M allocs, 1.72 GB,
4 arenas). The target is not the variable — the backend that compiled the
*running compiler* is.

## Fix direction (not yet done)

`devdocs/dev/ir-as-substrate.md` says push generality down. The recogniser is
pure IR-shape analysis with nothing x86-64 about it, and `PXXStrAppend` is an
ordinary 3-argument registered procedure that every backend can already emit a
call to. So the shape to aim for is: recognise in the shared IR layer, lower to
a normal call, and let x86-64 keep or drop its hand-emitted shim — rather than
hand-writing the same shim five more times, which is the second-path-that-stays-
broken this repo already has a note about.

The guards on `IRIsSelfStrAppend` are load-bearing and must move with it: LHS an
exact load of the same symbol, no by-ref params, RHS provably side-effect free
(append evaluates the right operand *before* reading the destination, concat
reads the destination first, and `s := s + f()` where f assigns to s tells them
apart).
