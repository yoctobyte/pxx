---
slug: bug-a-a-refcount-test-passes-at-o2-and-fails-at-o0-and-o1
track: A
prio: 60
type: bug
blocked-by: []
status: done
found: 2026-09-01
found-by: frankZ
owner: unassigned
summary: "`test_threadsafe_refcount_lockfree` prints TSRCLOCKFREE FAILED at -O0 and -O1 and TSRCLOCKFREE OK at -O2 and -O3, with rc=0 every time — a silent wrong answer that changes with the optimisation level. Two rows: a string literal's handle is not born saturated, and its count is not bit-identical after SetLength churn. Both levels must be correct, so one of the two answers is a bug and it is not yet established which. Invisible until 2026-09-01 because the program did not build under optdiff at all and the -O2 arm was comparing -O2 against -O2."
---

# A refcount test passes at -O2 and fails at -O0/-O1

Measured 2026-09-01 by frankZ at `c9602d5ce`, binary `76c8be9064e0`.

```
DEFAULT  rc=0 : TSRCLOCKFREE OK
-O0      rc=0 : TSRCLOCKFREE FAILED
-O1      rc=0 : TSRCLOCKFREE FAILED
-O2      rc=0 : TSRCLOCKFREE OK
-O3      rc=0 : TSRCLOCKFREE OK
```

Deterministic: six runs of each binary produce a byte-identical output, and 60
runs of the -O1 binary exit 0 every time. The exit code is 0 in all five
cases, so nothing in the tier chain that reads only rc can see this.

The two failing rows:

```
FAIL literal handle is born saturated
FAIL literal count still bit-identical after SetLength churn
```

Both are about a STRING LITERAL's refcount handle. A literal's count is
supposed to be saturated — the sentinel that means "never free this, it is in
.rodata". At -O0/-O1 it is apparently not, or the test's way of reading it
(`PWord(Int64(Pointer(v)) - 16)^`) sees something different there.

**Which answer is right is not established and that is the work.** `-O2` being
the default does not make it the reference; `compiler.pas:908` calls `-O0` the
byte-identity reference. CLAUDE.md is explicit that both must be CORRECT, so
this is one bug either way: either the literal is mis-saturated below -O2, or
it is mis-read above it.

## Why nobody saw it

Two harness holes, both closed by `baae75b6b`:

1. The program **did not build** under optdiff. It reaches `__pxxclone`, which
   is refused without `--threadsafe`, and optdiff counts a build-fail as a
   skip. It had been leaving the sweep silently.
2. Even once it built, optdiff's baseline was compiled with **no -O flag**,
   which is -O2 — so the `-O2` arm compared -O2 against -O2 and could not
   report anything. With an explicit -O0 baseline the sweep now names it on the
   -O2 and -O3 arms.

So the first shard run that could see this program at all is the one that
found it. It blocks [[umbrella-one-full-tier-run-with-no-red-tier]] — optdiff
lives in the `opt` tier, and `pin_is_green` requires every judged tier green.

## Resolved — 2026-09-01, frankZ. The compiler is right and the TEST over-specified.

`EmitStaticLitHandle` (`compiler/ir_codegen.inc:4374`) opens with
`if OptLevel < 2 then Exit;`, and the paragraph above it says so at length: the
static-literal handle — a ready-made saturated header already in the image, no
allocation, no copy — is used at **-O2 and above, since `440c822e6` promoted it
from -O3**. Below that a literal becomes an ordinary refcounted heap copy. The
REPRESENTATION is emitted unconditionally at every level ("a pool that changed
shape with the optimisation level would be two layouts to keep sound"); only
its USE is gated. Both shapes are correct.

Measured, `-O0` vs `-O2`, the same six-line probe:

```
-O0  ptr=136961851392032   (an mmap heap address)
-O2  ptr=4265208           (a static address inside the image)
```

So `Check(litRC0 >= $40000000, 'literal handle is born saturated')` asserted an
**-O2-only representation**, and with it the whole program printed
`TSRCLOCKFREE FAILED` at -O0/-O1 and `OK` at -O2/-O3 with `rc=0` throughout.

## What the rows now assert

The test's purpose survives the split: a literal handle must not be corrupted
by concurrent churn. That is checkable under either shape.

- The birth row records WHICH shape is in play (`saturated` or `one counted
  ref`) instead of demanding one.
- The churn row moved to **after** `SetLength(arr, 0)`. A saturated handle
  reads `litRC0` at both points; a counted one legitimately reads
  `litRC0 + (elements holding it)` while the array is live, so comparing
  mid-churn was asserting the -O2 shape rather than the property.

**The moved row is not vacuous, and I measured that rather than assuming it.**
Mid-churn, at -O0, `RC(lit)=22` against `litRC0=1` — 21 live array elements —
so the post-drop equality is a real reconciliation of 21 retains against 21
releases. At -O2 both readings are the saturated sentinel. A churn that loses
or double-counts a reference, which is what a raced retain/release looks like,
fails the row under either shape.

Green at all five: DEFAULT, -O0, -O1, -O2, -O3 — `fail=0 TSRCLOCKFREE OK`.

This was the umbrella's last wired blocker.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ad55e4dcc.

## Follow-up 2026-09-02 (frankC, Track A) — same diagnosis, reached independently, plus two rows

I worked this ticket concurrently and landed into the conflict. Recording the
agreement first, because it is worth more than the additions: **two sessions
reached the same diagnosis from different instruments.** The resolution above
used the literal's POINTER (an mmap address at -O0 against an in-image address
at -O2); I used the META word and the refcount together:

```
        meta   static-flag   rc born   rc w/ 21 array copies   rc after drop
-O0     5120   FALSE               1                      22               1
-O2     5376   TRUE       1073741824              1073741824      1073741824
```

Those fail differently — a pointer says where the block is, a meta flag says
what the runtime thinks it is — so the agreement is corroboration rather than
two readings of one instrument.

**Read that table with the right instrument.** It was taken at `480d4584403c`,
before `8761ea55b` fixed the builtin `PWord` to mean `^UInt16`, and a probe that
spells the read `PWord` now answers **0** for the -O2 refcount, because
`$40000000`'s low sixteen bits are zero. Re-taken at `0f1d03315f4e` through an
explicit `^NativeInt` the numbers above are unchanged and correct. The -O0
column is identical under both widths — everything in it fits in sixteen bits —
so the wrong instrument is invisible below the gate and wrong above it. Anyone
reproducing this needs the wide pointer; `uses builtinheap` also supplies one,
but only by leaking that unit's private name, which is the bug `8761ea55b` was
about and not something to rely on. Also confirmed from the other side: at -O0 two
spellings of the same literal get DIFFERENT handles, at -O2 they share one.

Two changes on top, both measured, neither a correction:

**1. The birth row now branches on the meta flag instead of accepting either
count.** `Check((litRC0 >= $40000000) or (litRC0 = 1), ...)` records the split
correctly and accepts one state that matters: a block whose meta says STATIC
carrying a count of 1 — a literal in the data section that `PXXStrDecRef` can
walk to zero and free, which is the exact failure `MSTR_STATIC_RC` exists to
prevent. It satisfies the second arm. Deciding the shape from the META word (an
independent field) and asserting the REFCOUNT against it rejects that state, and
makes the predicate self-guarding in both directions: forcing `IsStaticBlock`
False gives -O2 `fail=2`, forcing it True gives -O0 `fail=1`. A broken predicate
cannot route a level into the wrong arm and pass, because each arm asserts a
count the other representation does not have.

**2. A mid-churn row, restored for the counted shape only.** The post-drop row
is right and is the one both shapes share, but the two fail differently:
post-drop equality reconciles retains against releases in AGGREGATE, so a lost
increment matched by a lost decrement returns to `litRC0` and passes it. The
mid-churn row names the number that must be there while the references are
live, against `nLit` counted in the fill loop rather than written as 21.
Control: perturbing it to `litRC0 + nLit + 1` gives -O0 `fail=1`, -O2 `fail=0`.

Worth stating plainly, since it is the reason the -O0 arm earns its keep:
**a saturated count cannot detect a lost increment or an over-release at all.**
It is the same number whatever happens to it. So at -O2 and above this file's
coverage of the SetLength retain/release loops rests on the payload rows, and
below it rests on the counted rows — which is the opposite of how the original
file was weighted.

Still green at all five levels.

### One thing this invalidated, in both our versions

**`tools/optdiff.sh` cited this exact divergence as the positive control for its
own -O0-baseline fix, and that control is now spent** — the program it names no
longer reports DIFF on any arm. The comment has been corrected to say so and to
tell the next reader they need a new control, rather than left to be re-run by
someone who would find it silently passing. A dead control that still reads as
live is the same animal as the -O2-against--O2 baseline it was written about.

### Neither version catches this, and it is not in scope here

Nothing in the suite asserts that **-O2 actually USES the static handle.** If
`EmitStaticLitHandle` stopped firing, the literal would become a heap copy, both
our versions would take the counted arm, and every row would pass — correctly,
because the program would still be correct, just slower by the 9.28% of uforth's
profile that motivated the pass. That is a performance regression with no guard,
and it belongs to whoever owns the pass rather than to this test.
