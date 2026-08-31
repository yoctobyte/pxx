---
slug: bug-o-the-in-place-string-append-is-x86-64-only-so-every-other-backend-is-quadratic
track: A
prio: 92
type: bug
status: done
resolved: af07a59ff
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "FIXED 2026-08-31, all six backends. Two defects of one shape -- an optimisation living only in the x86-64 emitter with every other backend routed to a correct-but-quadratic shared path -- and the one this title names was NOT the one that mattered. (a) PXXStrSetLen always reallocated and copied, so `SetLength(s, Length(s)+1)` copied the whole string per call; AppendChar in lexer.inc does exactly that per character, which made the COMPILER'S OWN string building O(n^2) everywhere but x86-64. Fixed in the runtime -- in place when sole-owner and APPENDABLE with capacity, 2x only when an existing string grows -- so all six targets got it at once. (b) `s := s + x` had IRIsSelfStrAppend and its emitter in ir_codegen.inc and nowhere else; the recogniser is now forwarded in compiler.pas and i386, arm32, aarch64, riscv32 AND xtensa each emit a 2-argument call to the new runtime wrappers PXXStrAppendStr/Char. 20000 appends: 19780 allocations -> 16 on every target. ACCEPTANCE: the i386-hosted compiler builds compiler.pas natively (rc=0), and the x86-64-cross-built i386 compiler, its child and its grandchild are all three byte-identical (95b703fd1bc5bc5d) -- a true i386 fixedpoint it had never reached; arenas 13-then-SIGSEGV -> 4. NOT a 32-bit bug: aarch64 is 64-bit and was equally quadratic. Every xtensa measurement here was taken under --xtensa-soft-mulhigh, which qemu-xtensa requires for any 64-bit multiply."
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

## On ESP this is functional, not performance (frankS, 2026-08-31)

"Quadratic" reads as an -O ticket and on xtensa it is not one. Track S's primary
target is an S2/S3 with a few hundred KB of RAM; the arena IS the address space.
A 20000-character string built by append churns 4.4 GB and peaks at 13 arenas of
256 MiB on a hosted target -- on an ESP image the same program cannot start.
That is most ESP programs that log or format anything.

It also independently confirms the fix direction: lowering the recogniser into
the shared IR and emitting an ordinary call means xtensa and riscv32 get this
without anyone hand-encoding an append fast path into the two instruction sets
that already carry the most open codegen tickets.

## 2026-08-31 — acceptance

```
  x86-64 cross-built i386 compiler   95b703fd1bc5bc5d
  built by itself (gen2)             95b703fd1bc5bc5d
  built by gen2   (gen3)             95b703fd1bc5bc5d
```

Three generations, one sha. Before this the first of those three segfaulted at
19780 allocations with 13 arenas mapped. This is i386 only -- it is not a claim
about arm32, aarch64, riscv32 or xtensa hosting, none of which was run.

## 2026-08-31 — what it actually was, and what is left

**I got the cause wrong first, and the ticket's own named residual is what
caught it.** I fixed the append recogniser for i386 alone, re-ran the self-build,
and it died with the allocation profile *unchanged* (19780 allocs, 4.47 GB, 13
arenas). So the compiler's 4.4 GB was never the append path.

Attribution, measured: I tagged PXXAlloc by runtime entry point. **1629 of the
1641 large allocations, carrying 5.06 GB, came from `PXXStrSetLen`** -- not
concat, not append. `AppendChar` in `lexer.inc` is `SetLength(dst, len + 1)`
followed by a single character store, and `PXXStrSetLen` allocated a fresh block
and copied the whole string every time. Its own header names the hole: the cross
backends route there *"instead of the x86-64 inline resize"*.

(That tag instrument was **sticky** -- it recorded the most recently ENTERED
helper rather than the innermost, and it misattributed the same sizes to
different helpers on the two hosts. It is removed rather than committed; I am
recording that it misled me before it helped.)

The fix is in the runtime, so it lands on every backend at once: grow in place
when the block is sole-owner and APPENDABLE with spare capacity, on the same
terms `PXXStrAppend` already uses, and over-allocate 2x only when an EXISTING
string grows -- a first `SetLength` or a shrink still allocates exactly.

| idiom, 20000 iterations | x86_64 | i386 | arm32 | aarch64 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| `SetLength(s, n+1)` | 16 | 12 | 12 | 10 | 12 |
| `s := s + 'x'` | 16 | 16 | 16 | 16 | 16 |

(Final, after all four backend arms landed. xtensa is not in the table because
its integer-printing bug makes the census unreadable there; measured instead by
comparing lengths and characters, and both loops are correct on it.)

Semantics checked as well as cost: grow, shrink, regrow-with-zero-fill, and
shrink of a static literal, all correct on both hosts.

### xtensa — landed, after I removed it once by mistake

I wrote the xtensa arm, saw `s := s + 'b'` die with an illegal instruction on a
local as well as a global, could not explain it, and REMOVED it rather than ship
it. That was the right instinct applied to a wrong reading: the SIGILL was
qemu-xtensa refusing MUL32HIGH, which no core implements, and which every
numeric output hits too because div-by-10 strength-reduces into a 64-bit
multiply. frankS pointed at `tools/run_target.sh:95`, which has documented it
all along. Rebuilt with `--xtensa-soft-mulhigh`, the identical arm passes:
16 allocations for 20000 appends, all correctness checks green.

**Every xtensa verdict must name that flag**, per run_target.sh -- under it the
emulator is not bit-identical to hardware for multiplies.

Filed and then rejected the same day:
`rejected/bug-a-an-int64-multiply-dies-with-an-illegal-instruction-on-xtensa`.

### The original write-up of the attempt, kept because the diagnosis was wrong

aarch64 and riscv32 landed the same ~20-line arm as i386 and arm32.

**xtensa was written and then removed rather than shipped.** The arm compiled
and died with an illegal instruction on `s := s + 'b'` for a LOCAL as well as a
global, where the concat path is correct. What was tried, for whoever picks it
up: CALL0 puts arg0 in a2 and arg1 in a3, so the emitter did
`IREmitNodeXtensa(rhs)` (a2 = value), `mov a3, a2`,
`EmitSlotAddrXtensa(a2, sym)`, then `EmitCallProc` -- with the extra
`mov a10,a2 / mov a11,a3` under the WINDOWED ABI. Both address helpers
(`EmitFrameAddrXtensa`, `EmitLoadGlobAddrXtensa`) write only their `rd`, so a3
surviving them was checked and is not the hole. The neighbouring concat path
uses `XtensaPushA2` to spill rather than holding a value in a3 across a
sequence, which is the first thing to try.

**Debugging xtensa is unusually expensive right now** and that is worth knowing
before starting: `WriteLn` of an Integer dies with SIGILL there, which
confounded three of my probes before I noticed, so any xtensa test must report
through string literals only. See
`bug-a-an-int64-multiply-dies-with-an-illegal-instruction-on-xtensa`.

xtensa DOES get fix (a), the one that mattered for memory: its `SetLength` loop
is now geometric like everyone else's.

## Fix direction for what remains

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
