---
track: A
prio: 70
type: bug
blocked-by: []
summary: "x86-64 releases an owned managed-string operand after a CONCAT (ir_codegen.inc:6105/6110) and not after a COMPARISON, so `if F(x) = 'lit'` leaks F's result on every evaluation — 40 bytes per iteration, measured as 401032 bytes over 10000 iterations against 1032 on wasm32 and 0 under FPC. Present on x86-64 ALONE: i386, arm32, aarch64 and riscv32 each carry the release at all THREE sites (concat, equality, ordered), x86-64 at one. Exact mirror of bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target, which was the same predicate missing from the four cross backends while x86-64 had it. Silent, unbounded, and in one of the most common idioms in the language."
status: new
owner: ""
---

# A string function result in a COMPARISON leaks on x86-64

- **Type:** bug (codegen, managed-string lifetime) — **Track A**
  (`compiler/ir_codegen.inc`).
- **Filed:** 2026-08-28 by the wasm32 lane (branch `wasm`), which found it
  while building the same lowering for its own target and could not reproduce
  the native build's heap figure.
- **Affects:** the **default target**, at `-O0` and above. Not a cross-target
  gap — the cross targets are the ones that are right.

## The measurement

```pascal
program Rep;
var i, n: Integer; b: Boolean; p1, p2: Pointer;
function Name: string;
begin
  Name := 'one';
end;
begin
  Val(ParamStr(1), n, i);
  for i := 1 to 100 do b := Name = 'one';      { warm the free lists }
  p1 := PXXAlloc(1024, 8);                     { a size the loop never frees }
  for i := 1 to n do b := Name = 'one';
  p2 := PXXAlloc(1024, 8);
  writeln(n, ' iterations -> heap advanced ', NativeInt(p2) - NativeInt(p1));
end.
```

1024 bytes is deliberate: the loop allocates nothing of that size, so the
probe can never be satisfied from a free list and every call bumps the arena.
The advance is therefore (one probe block) + (whatever the loop failed to
release).

```
$ pascal26 rep.pas rep && ./rep 0      ;  0 iterations -> heap advanced   1032 bytes
$ ./rep 1000                           ;  1000 iterations -> heap advanced  41032 bytes
$ ./rep 10000                          ; 10000 iterations -> heap advanced 401032 bytes
```

**Exactly 40 bytes per iteration** — one `Name` result block, never released.

Two independent oracles say this is the bug and not the measurement:

| build | 10000 iterations |
| --- | --- |
| pxx **x86-64** (default) | 401032 bytes |
| pxx **wasm32** (branch `wasm`, same source, same frontend) | 1032 bytes |
| **FPC** 3.x, same program via `GetHeapStatus.TotalAllocated` | 0 |

## The cause, and it is structural

`IRNodeOwnsManagedStr` answers "does this node hand over a +1 reference, so the
consumer must release it". A concat result and a call result both do. x86-64
asks it in exactly one place:

```
$ grep -c IRNodeOwnsManagedStr compiler/ir_codegen.inc          # concat only
```

`ir_codegen.inc:6105` and `:6110` release the two operands of a **concat**. The
comparison arms a few hundred lines down — `EmitStrCmpReg` for `=`/`<>` at
`:6556`, `EmitAnsiStrCmp3Reg` for the four ordered operators at `:6565` — have
no release at all.

Every cross backend has **three** pairs of release sites, not one:

| backend | concat | `=` / `<>` | `<` `<=` `>` `>=` |
| --- | --- | --- | --- |
| `ir_codegen386.inc` | 2177/2182 | 2465/2469 | 2536/2540 |
| `ir_codegen_arm32.inc` | 1831/1836 | 1918/1923 | 1968/1973 |
| `ir_codegen_aarch64.inc` | 1541/1546 | 1631/1636 | 1680/1685 |
| `ir_codegen_riscv32.inc` | (concat) | 2015/2020 | (ordered) |
| **`ir_codegen.inc` (x86-64)** | **6105/6110** | **— none —** | **— none —** |

So this is not "a target was forgotten". It is the **exact mirror** of
`bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target`, whose
write-up sits in the comment at `ir_codegen.inc:6096`: there the predicate was
right on x86-64 and missing from four cross backends. Here it is right on four
cross backends and missing from x86-64. One predicate, three sites, five
backends — fifteen places where the answer has to be repeated, and the repo has
now been wrong at both ends of that matrix.

That comment already names the shape (*"this was the FIFTH hand-written copy of
that predicate"*) and fixing the copies is what it did. It did not remove the
need for copies, which is why the other half of the matrix stayed broken for
however long.

## Why it matters more than the byte count

`if SomeFunction(x) = 'literal'` is not an exotic construct — it is how Pascal
code branches on a computed string. The leak is silent, unbounded, and
proportional to how often the branch is evaluated, so it presents as a
long-running program growing without a visible allocation site. Nothing reports
it: the answers are all correct.

40 bytes is the block for a 3-character result. A realistic result string costs
proportionally more.

## Fix

The narrow fix is six release sites in `ir_codegen.inc`, copying `:6105/:6110`
into the equality and ordered comparison arms, guarded the same way
(`IntToTypeKind(IRTk[side]) = tyAnsiString and IRNodeOwnsManagedStr(side)`).
That is what makes the measurement above read 1032 at every count.

The wider question is whether the temp-release belongs at fifteen call sites at
all. Both halves of this bug are the same defect — *a predicate the emitters
must remember to ask* — and the second half was found only because a sixth
backend was written and its author diffed a heap figure. There is no test that
would have caught either. **Worth considering with the fix:** a single
`IRReleaseOwnedStrOperands(left, right)` hook that each backend calls once per
string-operand-consuming site, or a check that greps for the three site kinds
and asserts each is paired with a release — the same shape as the `abi.inc`
oracle. Do not close this ticket with six copies and no note about the
sixteenth.

## Notes for whoever takes it

- The wasm32 lane's own lowering (branch `wasm`,
  `WasmStrReleaseTemp` in `ir_codegen_wasm32.inc`) has all three sites and is a
  worked reference for the shape, but it is not a merge dependency: this fix is
  entirely inside `ir_codegen.inc`.
- `test/wasm/check_strop.sh` on branch `wasm` asserts, deliberately, that the
  NATIVE build still leaks — so that check will fail by design when this lands,
  which is the signal to rewrite its note and diff the figure against native
  again instead of asserting it independently.
- Frozen strings (`tyString`) are unaffected: they are buffers, not handles,
  and own nothing.
