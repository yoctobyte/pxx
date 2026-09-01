---
slug: bug-a-xtensa-allocates-twice-per-virtual-call-returning-a-string-and-leaks-one
track: A+S
prio: 45
type: bug
status: done
found: 2026-09-01
found-by: frankB
owner: ""
blocked-by: []
summary: "FIXED (frankC, 2026-09-02, 57e35555e). NOT a string bug and not an allocation bug: xtensa EMITTED every virtual call twice when its result was used, so the callee RAN twice and every side effect happened twice — an Integer-returning virtual call doubles identically (200 calls per 100 iterations). The doubled allocation count was the shadow. Cause: the statement walker's case ends in `else IREmitNodeXtensa(i)` and IR_VIRTUAL_CALL had no arm, so the catch-all emitted it at statement level and the parent emitted it again; riscv32 and arm32 both carry the IRStmtRoot-guarded arm. NOTE: this ticket's literal-result rows (1871/933/938) do not reproduce at HEAD — a virtual call returning a literal is 1/0/1, same as x86-64."
---

# xtensa allocates twice per virtual call returning a string, and leaks one

Split out of
[[refactor-a-the-owned-string-release-predicate-is-hand-copied-across-five-backends]]
rather than fixed with it: the ownership fix landed and this survived it, which
makes it a different defect and not a leftover.

## The measurement

`s := o.Make(i)` in a 4000-iteration loop, `Make` a **virtual** method returning
a fresh `AnsiString`, built `-dPXX_ALLOC_CENSUS`.

**At HEAD, before the ownership fix** — every backend leaked totally, which is
the bug that fix addressed:

| target | allocs | frees | live |
| --- | ---: | ---: | ---: |
| arm32 | 3799 | 0 | 3799 |
| riscv32 | 3799 | 0 | 3799 |
| xtensa | **7707** | 0 | **7707** |

**After the ownership fix** — everyone else is clean, xtensa is not:

| target | allocs | frees | live |
| --- | ---: | ---: | ---: |
| x86-64 | 3799 | 3796 | 3 |
| arm32 | 3799 | 3796 | 3 |
| riscv32 | 3799 | 3796 | 3 |
| xtensa | **7707** | 3851 | **3856** |

## What the numbers say, before anyone theorises

**The allocation count was ALREADY doubled at HEAD**, so the extra allocation is
not something the ownership fix introduced — it predates it and is independent
of it. 7707 vs 3799 is one extra managed string per iteration.

**The residual leak is almost exactly the extra allocations**: 3856 live against
3908 extra allocs. That is the shape of "the second string is never owned by
anyone, so nothing ever releases it", and it means **the leak is probably a
symptom of the double allocation rather than a second independent bug.** Find
the extra allocation first; the leak may disappear with it.

Per `devdocs/dev/root-cause-over-microfix.md`: do not go looking for a missing
DecRef until the extra IncRef-worthy allocation is explained.

## What is already ruled out

- **Not the ownership predicate.** The direct-call arm (`MakeStr(i) + MakeStr(i)`)
  and the indirect-call arm (`fp := @MakeStr; s := fp(i)`) both settle at the
  x86-64 numbers on xtensa after the fix, and both are wired as
  `test/test_managed_str_ownership_leaks.pas`. Only IR_VIRTUAL_CALL misbehaves.
- **Not a Call0/windowed difference** — unmeasured, and the first thing to check.

## Why the regression test does not cover it

`test/test_managed_str_ownership_leaks.pas` deliberately omits the virtual arm
and says so in its header. Wiring it today would pin a known-bad census as the
expected output on xtensa, which is worse than no coverage: it would go green
and stay green through the fix. **Add the virtual arm to that file as part of
closing this ticket** — the file is already wired into all five per-arch targets
and compares against the x86-64 build, so it costs one block and no new plumbing.

## Repro

```
./compiler/pascal26 -dPXX_ALLOC_CENSUS --target=xtensa --platform=posix \
    --xtensa-soft-mulhigh <probe>.pas /tmp/vl_xt
tools/run_target.sh xtensa /tmp/vl_xt | grep allocs=
```

with the probe being a class holding one `virtual` function returning
`AnsiString`, called in a loop and assigned to a string variable. Compare against
the same source built for x86-64.

## Narrowed considerably — 2026-09-01, frankB, second pass

Found again independently by an N-growth sweep across backends (`live` at
N=1500 minus at N=500), which flagged only `obj_virtual` and `len_of_virtual`
and only on xtensa. arm32 and riscv32 are clean, so this is not a cross-backend
family — it is xtensa's virtual dispatch alone.

### It is VIRTUAL DISPATCH, not being a method, and not the callee's work

Same class, two methods with identical bodies, 1000 iterations, xtensa:

| callee | allocs | frees | live |
| --- | ---: | ---: | ---: |
| `function GetN: AnsiString;` (non-virtual) | 921 | 918 | 3 |
| `function GetV: AnsiString; virtual;` | **1871** | 933 | **938** |

Non-virtual is byte-identical to x86-64's numbers. So the method body, the
Char→string conversion and the store path are all fine; only the dispatch
differs.

### The callee does not need to allocate at all for this to happen

The sharpest version: make the virtual method return a plain **literal**,
`GetV := 'abcdef'`, which allocates NOTHING on x86-64.

| target | allocs | frees | live |
| --- | ---: | ---: | ---: |
| x86-64, virtual → literal | **1** | 0 | 1 |
| xtensa, non-virtual → literal | 921 | 918 | 3 |
| xtensa, **virtual** → literal | **1871** | 933 | **938** |

**xtensa allocates ~1871 heap strings to return a constant.** So this is not the
callee failing to hand over ownership of something it built — there is nothing
to hand over. The strings are being materialised by xtensa itself.

### Two distinct behaviours, and only one is this ticket

1. **xtensa materialises a literal string function result on the heap at all**
   (921 for 1000 iterations, where x86-64 does 1). Both virtual and non-virtual.
   Everything allocated is freed, so this is an EFFICIENCY gap, not a leak. It
   may deserve its own ticket; it is not this one.
2. **Virtual dispatch does it TWICE and releases only one** (1871 allocs, 933
   frees). That is this ticket, and the residue is the unreleased half.

So the earlier note stands and is now specific: **find the extra materialisation,
not a missing DecRef.** The leak is its shadow — nothing owns the second copy
because nothing asked for it.

### Where it is not

`IR_VIRTUAL_CALL` in `ir_codegen_xtensa.inc:4238` only dispatches: push args,
load arg regs, read the VMT pointer, `callx`. It contains no allocation and no
string handling, and it refuses aggregate/frozen-string results outright via
`IRCallDest[node] >= 0`. The IR is target-independent and x86-64 is clean from
the same IR, so the divergence is in xtensa's emission around the call, not in
the IR or the frontend.

## FIXED 2026-09-02 (frankC) — it was not about strings, and not about allocation

Landed `57e35555e`. The narrowing in this ticket was right about where to look
and wrong about what was there: **the extra allocation is not an extra
materialisation of the result. The whole virtual call was emitted twice, so the
callee RAN twice**, and the second allocation is simply the second run's.

### The measurement that turned it

A counter incremented inside the callee, 100 iterations, rather than an
allocation census:

| shape | xtensa | x86-64 / arm32 / riscv32 |
| --- | ---: | ---: |
| `s := o.FStr(i)` (AnsiString result) | **200** | 100 |
| `k := o.FInt(i)` (**Integer** result) | **200** | 100 |
| `k := Length(o.FStr(i))` | **200** | 100 |
| `WriteLn(o.FStr(i))` | **200** | 100 |
| `o.PVoid(i)` (result discarded) | 100 | 100 |

So this is **not a managed-string defect**. An Integer-returning virtual call
doubles identically and moves no counter a census can read. Every side effect of
every virtual function ran twice on xtensa — a write, a file append, a device
poke, not only an allocation. The leak was the half of the doubled work that
nothing owned, exactly as this ticket predicted ("the leak may simply be its
shadow"); the prediction was right and the mechanism underneath it was bigger.

Only the discarded-result row was correct, and that is the tell: that shape has
just the one emission to begin with.

### Cause

`ir_codegen_xtensa.inc`'s statement walker ends its `case IRKind[i] of` with

```
else
  IREmitNodeXtensa(i);
```

and **IR_VIRTUAL_CALL had no arm in it at all**. The catch-all emitted it at
statement level; the parent consuming the value emitted it again. riscv32
(`:4305`) and arm32 (`:4662`) both carry an `if IRStmtRoot[i]` arm, and
`IRMarkStatementNode` (`ir.inc:889`) sets `IRStmtRoot` for exactly
IR_VIRTUAL_CALL and IR_CALL_IND — the reader existed and xtensa was the only
backend not reading it. Fixed with that same arm.

The comment three lines above the `else` documents this failure mode for
IR_ATOMIC — *"a value node consumed by its parent store ... emitting it at
statement level TOO runs the read-modify-write twice — riscv32 and arm32 both
paid for this one"*. One arm of a double case was fixed and the sibling was
never grepped for.

Proven, not argued: a probe on every entry to the emitter shows ONE node emitted
twice (node 24, codelen 231066 and 231126, either side of the walker reaching
its store), and qemu disassembly shows two identical VMT dispatch sequences 60
bytes apart, both executed. Not the relaxation retry — that doubles every node,
and the sibling call in the same run printed once.

### Two claims in this ticket do NOT reproduce at HEAD

Recorded because they were the ticket's sharpest evidence and would send the
next reader somewhere there is nothing to find:

> *"xtensa allocates ~1871 heap strings to return a constant"* — `xtensa,
> virtual → literal: 1871 / 933 / 938`

Measured now: `GetV := 'abcdef'` through a virtual call is **1 / 0 / 1 on
xtensa, identical to x86-64**. So is the non-virtual literal row (the ticket has
921/918/3). Both literal rows are clean, and the doubling needs the callee to
actually allocate.

Note the triple `1871 / 933 / 938` is EXACTLY the concat probe's numbers at 1000
iterations, which is what the row above it reports. I cannot tell from here what
produced that, and I am not asserting a cause — only that the literal rows do
not reproduce and the "two distinct behaviours" split built on them (the second
being "xtensa materialises a literal string function result on the heap at all")
has nothing under it at HEAD.

**Also: the census numbers in this ticket are CHECKPOINTS, not totals.**
`PXXCensusReport` fires on a geometric schedule (`CensusNext := CensusNext +
CensusNext div 8 + 1`, `builtinheap.pas:2365`), so the last line printed is the
last checkpoint reached, not the count at exit. It does not change the 2×
conclusion — both runs step the same checkpoint sequence — but a reader
comparing 7707 against 3799 as exit totals is comparing two lower bounds.

### Coverage

`test/test_virtual_call_runs_once.pas`, new, wired on **six** targets (x86-64,
i386, arm32, aarch64, riscv32, xtensa). It counts CALLS rather than allocations
— a census only sees this defect when the callee happens to allocate, which is
what kept it looking like a string bug. **Proven able to go red** against the
reverted arm (revert asserted by grep, not assumed): `FAIL: managed-string
result assigned ran 200 times, want 100`, rc=1.

Its last row is a positive control for the obvious wrong fix: adding
IR_VIRTUAL_CALL to the walker's do-nothing list silences the doubling and
deletes virtual PROCEDURE calls entirely, and that row fails in the opposite
direction.

This is instead of the virtual arm in `test_managed_str_ownership_leaks.pas`
that the ticket asked for. That file compares an allocation census, which is the
instrument that under-reports this.

### Residual, with an owner

Five more kinds are named in riscv32's and arm32's walkers and absent from
xtensa's — IR_LOAD_MEM, IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP, IR_DYNUNIQUE — so
they reach the same `else`. A side-effect counter driven through set literals,
`in`, set binops and dynamic-array unique does **not** double on xtensa; that is
what I measured, in those shapes, and it is not a proof about the catch-all.
Filed as [[bug-a-the-xtensa-statement-walker-emits-any-unnamed-node-kind-through-a-silent-else]].

### Measured at

compiler `8b592075e47e`, `converged after 1 round(s)`, `gate.sh quick` GREEN
with the FPC seed canary PASS (not SKIP). After the fix the original probe reads
`allocs=3799 frees=3796 live=3` on xtensa, byte-identical to the x86-64 oracle.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
