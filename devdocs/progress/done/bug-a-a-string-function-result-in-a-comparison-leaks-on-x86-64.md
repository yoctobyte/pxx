---
track: A
prio: 70
type: bug
blocked-by: []
summary: "x86-64 releases an owned managed-string operand after a CONCAT (ir_codegen.inc:6105/6110) and not after a COMPARISON, so `if F(x) = 'lit'` leaks F's result on every evaluation — 40 bytes per iteration, measured as 401032 bytes over 10000 iterations against 1032 on wasm32 and 0 under FPC. Present on x86-64 ALONE: i386, arm32, aarch64 and riscv32 each carry the release at all THREE sites (concat, equality, ordered), x86-64 at one. Exact mirror of bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target, which was the same predicate missing from the four cross backends while x86-64 had it. Silent, unbounded, and in one of the most common idioms in the language."
status: done
owner: frankB
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

## 2026-08-29 — FIXED (frankB). Three sites, not two, and the ticket named the wrong one.

Reproduced at HEAD before reading any code: 1032 / 41032 / 401032 at n = 0 /
1000 / 10000, exactly as filed. 40 bytes per iteration.

### The ticket's site list was wrong, in a way that mattered

It names `EmitStrCmpReg` (`=`/`<>`) and `EmitAnsiStrCmp3Reg` (ordered). There
are **three** comparison emitters on x86-64, and the leaking one is the third:

| block | guard | emitter | owned operand possible? |
| --- | --- | --- | --- |
| 1 | `=`/`<>`, either side `tyAnsiString` | `EmitAnsiStrCmpReg` | **yes — this is the leak** |
| 2 | `=`/`<>`, either side `tyString` | `EmitStrCmpReg` | **no — provably** |
| 3 | `<` `<=` `>` `>=`, either side managed | `EmitAnsiStrCmp3Reg` | yes |

Block 2 is the one the ticket asked for, and it is the one place a release
would have been **dead code**: it is the `else if` *after* block 1, so neither
side can be `tyAnsiString`, and a `tyString` is a frozen buffer that owns
nothing. Adding the pair there would have looked like a fix and changed no
emitted byte. That is recorded in a comment at the block rather than left for
the next reader to re-derive, along with the condition that would make it
needed.

### And the release cannot go around the emitter call

Blocks 1 and 3 each have **inline arms** for `AnsiString` vs `Char` that
compare in place and never reach the emitter at all. `F(x) = 'c'` takes one of
those, so a release attached to the emitter call site alone would still have
leaked, and the repro that found this bug would not have caught the remainder.
The save/release therefore wraps the **whole block**, covering all three arms
uniformly. Verified: the char arms are stack-neutral on both paths (`push rcx`
… `pop rax` on the equal path, `pop rcx` on the not-equal path).

### The fix

`ir_codegen.inc` only. Four helpers above `IREmitNode` — `IRStrCmpOwnsOperand`,
`IRStrCmpNeedsRelease`, `IREmitStrCmpSaveOperands`,
`IREmitStrCmpReleaseOperands` — so x86-64's three sites share **one** copy of
the predicate instead of three. Emitted only when an operand is actually
owned, so codegen for the ordinary borrow-vs-literal case is unchanged.

Contract relied on, and it was checked rather than assumed: `rax` = LHS,
`rcx` = RHS at every string-comparison emitter, and all three emitters are
stack-neutral and never reference `rsp`, so the saved slots survive the
comparison. (The `EmitB($50)` bytes inside two of them are ModRM in
`mov rdx,[rax-8]`, not `push rax` — a naive opcode grep says otherwise.)

**The `-O3` W1 hazard, ruled out both ways.** `w1RightReg` can put the right
operand in `r12..r15` instead of `rcx`, which would make `mov [rsp], rcx` save
garbage and release a wrong pointer. It cannot reach here: W1 is gated to
`W1AluRightEligible` — "the plain integer ops that read rcx as `<op> rax, rcx`
and nothing else — the string/set/float arms below run their own
multi-register sequences and keep the normal contract" — and `w1RightReg` is
consulted **zero** times anywhere in the comparison arms. Confirmed
structurally *and* measured at `-O0`/`-O1`/`-O2`/`-O3`.

### Measured

| program | before | after |
| --- | --- | --- |
| ticket repro, n=10000 | 401032 | **1032** |
| ticket repro, n=1000000 | (40001032) | **1032** |
| ordered + both char arms + `<>`, n=1000000 | — | **1032** |
| both operands owned (`F = F`) + nested concat, n=1000..10⁶ | — | **1112, constant** |

The 1112 is a one-time free-list effect, not a leak: constant from n=1000 to
n=1,000,000. Flatness across three orders of magnitude is the property, not the
absolute number.

Correctness: a 9-case program (borrow surviving 5000 comparisons, ordered
operators, call-vs-call, nested concat, both char arms, empty strings) is
**byte-identical to the FPC 3.2.2 oracle** at every `-O` level, and runs clean
under `-dPXX_HEAP_DEBUG`. Self-host fixedpoint converged (2 rounds, expected —
codegen changed); the compiler is itself a heavy user of string comparison.

### The census the ticket asked for, done by code and not by line number

All five backends now carry the release at all three site kinds. Verified by
which runtime helper each pair sits next to, **because the ticket's line
numbers are already stale** — it lists aarch64 at 1541/1631/1680 where the
pairs are actually at 1824/1914/1963:

| backend | Concat | StrEq | StrCmp3 |
| --- | --- | --- | --- |
| `ir_codegen386.inc` | 2177 | 2465 | 2536 |
| `ir_codegen_arm32.inc` | 1831 | 1918 | 1968 |
| `ir_codegen_aarch64.inc` | 1824 | 1914 | 1963 |
| `ir_codegen_riscv32.inc` | 2015 | 2049 | 2088 |
| `ir_codegen.inc` (x86-64) | 6177 | *(shared helper)* | *(shared helper)* |

**Sibling checked before closing:** the `AnsiString`-vs-`Char` inline arms exist
on x86-64 **and i386** (2 each) and on none of arm32/aarch64/riscv32. i386's
were measured directly — `C = 'x'` in a loop under `run_target.sh i386` is flat
at 1032 for n=0 and n=10000, so i386 already covers them. No second arm left
broken.

### What this does NOT fix

The ticket's wider question stands, and deliberately: **the predicate is still
hand-copied across backends.** This reduced x86-64 from three copies to one; the
cross-backend total is still twelve, in four files. A shared
`IRReleaseOwnedStrOperands` hook, or an oracle asserting each site kind is
paired with a release, would need to touch `ir_codegen386/arm32/aarch64/riscv32`
— outside this ticket's file and outside the dispatch. **Not attempted here;
left open as the sixteenth-copy problem the ticket names.**

Also unchanged, by design: `test/wasm/check_strop.sh` on branch `wasm` asserts
the native build still leaks. That assertion is now false and will fail — which
is the signal the ticket predicted, not a regression.

## Log
- 2026-08-29 — resolved, commit 0d91dc88f.

## 2026-08-30 (frank-optimize) — RE-VERIFIED at HEAD; the stale twin in `backlog_new/` removed

Dispatched to me as the top-ranked open Track A ticket. It was not open: the fix
landed at `0d91dc88f` on 2026-08-29 and a **second copy of this file was sitting
in `backlog_new/` with `status: new`**, so the ranker offered finished work at
p70. It had already been queued once for frankA before reaching me.

**Verified fixed before concluding anything**, at HEAD, self-host fixedpoint
`converged after 1 round(s)`, binary sha256 `aa78a7faf63a` (≠ pinned):

```
0 iterations -> heap advanced 1032
1000 iterations -> heap advanced 1032
10000 iterations -> heap advanced 1032
```

Flat, against the filed 1032 / 41032 / 401032. The helpers are live in
`ir_codegen.inc`: `IRStrCmpOwnsOperand` / `IRStrCmpNeedsRelease` /
`IREmitStrCmpSaveOperands` / `IREmitStrCmpReleaseOperands` at `:4763-4789`,
called at `:7131`/`:7179` (block 1, `=`/`<>`) and `:7241`/`:7244` (block 3,
ordered). `0d91dc88f` is an ancestor of HEAD.

### How a resolved ticket got back into a ranked folder

Not a mis-move. The file was correctly renamed `backlog_new/` → `done/` by
`0d91dc88f`. The copy came back with the **`wasm` branch landing**:

| commit | branch | `backlog_new/` | `done/` |
| --- | --- | --- | --- |
| `4af569658` (08-28) | wasm — filed it | yes | no |
| `0d91dc88f` (08-29) | master — fixed it, moved it | **no** | yes |
| `0571f4f9e` | master | no | yes |
| HEAD | after wasm landed | **yes** | yes |

`4af569658` is **not** an ancestor of `0d91dc88f`: the wasm lane filed this
ticket on its own branch, master fixed and moved it independently, and when the
long-lived `wasm` branch came back (three `Merge remote-tracking branch
'origin/master' into wasm` commits) it carried its own still-in-`backlog_new`
copy with it. A branch that outlives a ticket's whole lifecycle re-files it on
landing.

**`tools/progress.sh check` already catches this** and was reporting it:

```
DUPLICATE-SLUG: bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64
exists in 2 status folders (backlog_new/, done/) — the folder is the lock, so
the copy in the earlier folder reads as a live claim on finished work.
```

So the tooling gap is not detection. The finding sat in `check`'s output while
the ticket was dispatched twice from `next`, which does not run `check`.

### Diffed before deleting, per `check`'s own instruction

The `backlog_new/` copy is a strict prefix of this one — identical but for
`status`/`owner` frontmatter, with this file carrying 114 additional lines of
resolution. Nothing was lost; there was nothing to concatenate. Deleted.

**Swept for siblings:** every ticket slug across all status folders, exactly one
appeared twice (this one; the per-folder `README.md`s are by design). An isolated
resurrection, not a class — no campaign needed.

### Still open, and now filed

The "sixteenth copy" problem this ticket named is **not** fixed and now has its
own ticket:
`refactor-a-the-owned-string-release-predicate-is-hand-copied-across-five-backends`.
Census at HEAD — x86-64 routes its 5 comparison sites through the shared helper,
the four cross backends still hand-write `IRNodeOwnsManagedStr` 6-7 times each:

| backend | `IRNodeOwnsManagedStr` sites | via shared helper |
| --- | ---: | --- |
| `ir_codegen.inc` (x86-64) | 9 | yes (5) |
| `ir_codegen386.inc` | 6 | no |
| `ir_codegen_arm32.inc` | 6 | no |
| `ir_codegen_aarch64.inc` | 7 | no |
| `ir_codegen_riscv32.inc` | 6 | no |
| `ir_codegen_wasm32.inc` | 3 | no |
