---
slug: bug-a-xtensa-allocates-twice-per-virtual-call-returning-a-string-and-leaks-one
track: A+S
prio: 45
type: bug
status: new
found: 2026-09-01
found-by: frankB
owner: ""
blocked-by: []
summary: "xtensa allocates TWO managed strings per iteration where every other backend allocates one, for `s := o.Make(i)` with a virtual method returning AnsiString -- 7707 allocs against 3799 for the identical source. After the ownership-predicate fix in the same session, x86-64/arm32/riscv32 all settle at live=3 and xtensa settles at live=3856: the fix released one of the two, and the second allocation is never released by anything. So there are two distinct defects here, an EXTRA allocation and an unreleased one, and the extra allocation is the one to find first because the leak may simply be its shadow. Measured with -dPXX_ALLOC_CENSUS; the direct-call and indirect-call arms of the same predicate are clean on xtensa, so this is specific to IR_VIRTUAL_CALL."
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
