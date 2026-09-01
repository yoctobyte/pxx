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
