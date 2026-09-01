---
type: bug
track: A
prio: 6
summary: x86-64 inlines SetLength and its retain chain stops at kind 4, so promo and variant array elements are never retained — which is why the descriptor stride for kinds 5/6 cannot be emitted
tags: [O, memory-leak, promoint, variant, dynarray]
---

## The fork in the road

Every cross backend calls `PXXDynSetLen` (builtinheap.pas ~4353), which reads
`baseKind` from the descriptor and has correct retain AND release arms for all
of kinds 1/3/4/5/6. **x86-64 does not call it** — it inlines the whole of
SetLength in `ir_codegen.inc` at `IR_SETLEN_DYN` (~10592), and that inline
retain chain is:

    if slDepth > 1      -> retain sub-array handle
    else if slMek = 1   -> AnsiString incref
    else if slMek = 4   -> PXXIntfAddRef
    else                -> assume RECORD: EmitManagedRecordIntfWalk + Retain

Kinds **5 (promotable int)** and **6 (Variant)** fall into that final unguarded
`else` and are handed to `EmitManagedRecordRetain`, whose first line is
`if recId < REC_UCLASS_BASE then Exit` — and their recId is REC_NONE. So they
get **no retain at all**. The release emitted immediately afterwards is
`PXXDynArrayRelease`, which *does* have kind 5 and 6 arms.

This is the ninth site of the `ManagedElemKind` policy, and it missed a case —
exactly what that function's own header predicts of every copy of it.

## Why it currently only leaks

The asymmetry is invisible today because the anon dyn-array descriptor writes
`baseTypeRef = 0` for kinds 5/6, so the release half reads a stride of zero and
its `elSize > 0` guard declines too. Both halves decline: **balanced, and leaky.**

`9cb079528` widened that descriptor arm to emit the real stride, which woke the
release half **alone** — release without its retain — and turned the leak into a
double free. Measured: `test_promoint_array_cleanup` exit 139 with the widening,
exit 0 / `39000/39000` without. `a584e8fef` reverted the widening and recorded
the pairing requirement in `rtti_emit.inc`.

So the two changes are correct only **together**, and this ticket is the half
that has to land first.

## The leak that is open right now

    local `array of PromoInt`, heap-tier payloads, 1500 trips
      allocs=12347 frees=1371 live=10976      (measured both with and without
                                               the widening — this path never
                                               retained OR released)

    local `array of Variant`, 1500 trips
      allocs=4274 frees=1424 live=2850

## Exactly which cells leak — the matrix

4 element kinds x 4 container shapes, 1000 trips of 8 elements each, one
program per cell, `-O2 -dPXX_ALLOC_CENSUS`, live blocks at exit:

    element kind      local dyn   local fixed   record field   nested dyn
    AnsiString                4             3              4            5
    record + string           4             3              4            5
    PromoInt               7820            11             12         7805
    Variant                7708             3              4         7805

Read it as three facts:

- The leak is **kinds 5 and 6 in a DYNAMIC array only**. Two of four kinds, two
  of four shapes. Everything else reclaims.
- **Fixed arrays are clean** for promo and variant, so the element walk itself
  and ManagedElemKind's kind 5/6 answers are right — this is the dyn-array
  path alone, which is what points at the inline SetLength rather than at the
  policy.
- **Record fields are clean** for promo and variant, which is `2b70ff387` +
  `9cb079528`'s descriptor-writer half doing its job. That half was KEPT when
  `a584e8fef` reverted the stride; this row is the evidence it earns its place.

`nested dyn` (`array of array of T`) leaks at the same rate, so the depth>1 arm
needs the same treatment and is not covered by fixing the leaf case alone.

Use this table as the acceptance test: every cell must land in single digits.

## The sibling — fix it in the SAME change

`ir_codegen.inc` ~9889 (the copy-prefix retain on the symbol SetLength path)
has the identical `1 / 4 / else-assume-record` chain, **plus** a stride bug the
first site does not have: it advances

    if slMek = 3 then RecSize(...) else 8

and kinds 5 and 6 are **16-byte** slots on x86-64 (PromoInt64 = tag+payload,
Variant = tag+payload). That stride is latent only because the record walk it
emits is inert for a REC_NONE id — the loop strides wrong and does nothing.
**Add the arms there without fixing the stride and the new retain walks half
elements.**

## Doing it

Add `slMek = 5` and `slMek = 6` arms at both sites. The runtime halves already
exist and are the definition to mirror — `PXXDynArrayRetainImmediate`'s kind-5
and kind-6 arms (builtinheap.pas ~3769/~3790): kind 5 is
`if tag = PROMO_TAG_HEAP then PXXStrIncRef(payload)`, kind 6 is `PXXVarRetain`
(single argument, so its call shape is simpler than the kind-4 arm's). Consider
calling `PXXDynArrayRetainImmediate` once per element instead of hand-rolling
the arms a tenth time — one call, and it cannot drift from the release side.

Then re-widen the `rtti_emit.inc` arm (the comment there names this ticket).

**Gate: full tier, not quick.** `gate.sh quick` was GREEN on the broken commit;
only `--tier full` caught it, as `test-core#244`.

## A four-target red was raised against this premise — NOT cleared; see the correction below

Recorded so nobody re-raises it. **The premise above survives**; nothing in the
analysis changed.

Track T on seven published `test/test_managed_dynarray_field_leaks.pas` RED on
**aarch64, arm32, i386 and riscv32** (`bad=0d3d061121a7`) — exactly the four
backends this ticket exonerates by saying they delegate to `PXXDynSetLen`. That
looked like the premise failing, and frank-coordinator's argument for taking it
seriously was a good one: four backends failing *identically* points at shared
descriptor/retain logic rather than at one emitter.

**It did not reproduce in a local run.** The test was run on all four targets against
`origin/master` with in-flight work stashed, compiler `6b74eeb25a98`: `rc=0`,
every counter 1000. That baseline is precisely where a broken cross-path
descriptor/retain would show.

**The bracket closes the other reading.** Exactly one commit touches `compiler/`
or `lib/` between the red sha and origin/master — frankC's `b392fd5d0`, which is
i386-only and cannot explain aarch64, arm32 and riscv32 going green.

**The residual is not a codegen question and does not belong to this ticket:**
it is the second unreproducible red on seven that afternoon (the other was
`test-sqlite-threads-aarch64`, triaged as a timeout on a loaded box, ticket
`4982837ff`), so it is a question about the HOST. Owned by Track U / the T-host
thread, not by whoever works this ticket.

**One correction to what was circulating:** `a584e8fef` is the **revert**, not
the stride widening — `9cb079528` was the widening. The tree at the red sha
therefore has the descriptor **narrow**: safe-but-leaky, not a double free.
Anyone told otherwise would have hunted a double free that was not there.

The leak this ticket is actually about is real and measured on x86-64: promo
`live` 2955 / 5985 / 10779 growing linearly in trips, against 7 / 9 / 7 flat;
variant 7708 against 4.

### CORRECTION, same day — it RECURRED, so the section above is wrong

The "cleared" verdict rested on that local green and on the assumption that a
single-run red is a flake. Both premises failed within thirteen minutes.

| sha | time | wall | dynarray rows red |
| --- | --- | --- | --- |
| `0d3d061121a7` | 15:42:45 | 553.6s | 4 (new_red) |
| `66cda2103004` | 15:55:12 | 550.6s | 4 (still red) |

Two consecutive full runs on seven, all four cross targets, **both at normal
wall time** — the full-tier norm there is ~540-553s. The load explanation is
dead for these rows: neither run was slow, and the one genuinely slow run in the
window (`3e6249872671`, 678.4s) does not carry them.

The host is not sick either. Measured on seven at 15:55: load 8.10 / 14.85 /
17.27 across 24 cores, 2G used of 94G, 67G free, nothing swapping.

**So the local green and seven's red are both measurements, and they disagree.
The object of interest is the difference in METHOD** — the harness runs
`test-aarch64#...` and friends under qemu; a local run at `origin/master` may not
be the same execution. Neither side is asserted right here.

**The residual has an owner: it is a Track T harness-vs-local question**, not a
question about this ticket's premise, which remains untested by either result.

Two things learned that outlive this: a single-run red is not evidence of a
flake, and **a green that cannot be shown to run the same way as the red does
not refute it.** The first "cleared" write-up made both mistakes in one
paragraph.

### Who ran the local green — do not attribute it, identify it by its compiler

Two records credit that run to two different agents, and this section originally
said **frankB** because it inherited a topic-ownership correction (frankB owns
`test_managed_dynarray_field_leaks.pas`, having added it in `9cb079528`) and
applied it to the question of *who ran this particular run*. Those are different
questions and the second was never established.

**The run's identity is `compiler 6b74eeb25a98`, and that is the only part that
is evidence.** Both records agree on it, which is what shows it is one run
rather than two. The agent name adds nothing a reader of this ticket needs, and
a wrong owner on a disputed measurement misroutes whoever picks it up.

Commits do carry a `Claude-Session:` trailer that distinguishes agents — four
distinct session ids across the last 200 commits on origin/master — so
attribution is possible where it matters. Its limit: not every commit has one
(`a584e8fef` carries none), so **absence means unknown, never "someone else."**

### RESOLVED WHAT FAILED — read off seven's own job logs, 2026-09-01

The assertion that fails is **`assert_no_leak`, not `expect_same`**. From
`/tmp/testmgr-7nkwm2i4/test-<target>#<n>.log` on seven, all four verbatim:

```
assert_no_leak[aarch64/managed_dynarray_field]: LEAK — live=111 exceeds 50
  allocs=28165 frees=28054
assert_no_leak[i386/managed_dynarray_field]:    LEAK — live=111 exceeds 50
assert_no_leak[riscv32/managed_dynarray_field]: LEAK — live=111 exceeds 50
assert_no_leak[arm32/managed_dynarray_field]:   LEAK — live=111 exceeds 50
```

**`assert_no_leak` IS in the recipes** — `grep -c assert_no_leak Makefile` on
seven returns **39**. The reasoning that it appears only in the test's comment
and in none of the four recipes, and that therefore some `expect_same` counter
must differ, is wrong at its first step. No counter comparison failed; a
threshold did.

**All four targets report byte-identical counters**: `allocs=28165 frees=28054
live=111`, against a threshold of 50. (`bytes` differs — 942600 on aarch64,
902600 on the three 32-bit targets — which is word size, not behaviour.)
Against the local x86-64 run's `live=3`, the allocation trace agrees exactly and
**108 frees do not happen**.

**Four targets producing identical counters to the digit is not four bugs.** It
is one shared path, which is the argument frank-coordinator made first and then
talked itself out of. It also means this is a real reclamation difference on the
cross targets rather than a harness artefact — the jobs run under **qemu**
(`FAIL test-aarch64#147 qemu 1.2s`), but qemu does not invent 108 missing frees
identically on four ISAs.

**So the premise IS in question, and now for a stated reason.** This ticket says
the cross backends delegate to `PXXDynSetLen` and are correct. On this test they
leak 111 live blocks where x86-64 leaks 3. Whoever works this should start from
`PXXDynSetLen`'s release arm, not from the x86-64 inlining path. *(Refined below:
the release arm is correct and DECLINES — see the next section.)*

The local green remains true and remains scoped to x86-64: `live=3` passes a
threshold of 50, so a local run cannot see this at all.

### The four rows are red BY DESIGN, and the routing above is one step off

Verified from the run archive: the four jobs were **green in four consecutive
full runs** — 14:48, 15:01, 15:13, 15:27, `red=0` and not unreached — then red at
15:42, 15:55 and 16:07. A threshold that cannot pass cannot be green four times,
so neither the threshold nor word size is the cause.

Exactly three code commits land in that window, and only one can redden all four
targets: **`a584e8fef`** (`compiler/rtti_emit.inc`, `baseKind = 4/5/6` →
`baseKind = 4`). `5131e9cea` is a Pascal frontend check; `4924f1524` is i386
PC-relative and cannot touch aarch64/arm32/riscv32.

**Its own commit message states the trade**: *"both halves declined and the array
merely leaked"*, and *"the cost of reverting is a known leak, not a regression"*.
The revert deliberately chose a leak over the double free the widening had
caused, and it names the exit: **widen it on the day `ir_codegen.inc` grows kind
5 and 6 retain arms, not before.**

So `live=111` against a threshold of 50 is the **intended** trade, landing on an
assertion that does not know about it.

**Corrected routing:** `PXXDynSetLen`'s release arm is **correct and declines** —
`baseTypeRef` is 0 for kinds 5/6, so the walk reads stride 0 and `elSize > 0`
turns it away. Nobody should go looking for a broken release arm. **The work is
the kind 5/6 retain arms in `ir_codegen.inc`**, after which `a584e8fef` can be
un-reverted. (Credit: frank-coordinator, from the commit record.)

**Falsifiable prediction, recorded before the next tier.** `321271fc9`'s
`CENSUS_PORTABLE` strips the `sizes` lines and the `bytes=/reuse=/list=/bump=/
arenas=` tail, and **keeps `allocs=`, `frees=`, `live=`** — verified in the diff.
`assert_no_leak` reads `live=`. **So the four rows must stay red on the next full
run.** If they do, nothing new is wrong: the census fix was aimed at a real but
different defect, and "all eight rows verified SAME" is `expect_same`'s verdict,
not this assertion's.

### Falsified: the reds are NOT one x86-64 binary asserted four times

Each of the four recipes runs **two** `assert_no_leak` calls — the cross target
first, then x86-64 on the `_x64` companion (Makefile 14929/14930 aarch64,
14329/14330 i386, 15566/15567 riscv32, 17095/17096 arm32). So four identical
`live=111` values had a cheaper explanation available: **one x86-64 binary
asserted four times**, in which case the red never measured a cross backend at
all and this ticket must not claim it did.

Checked on seven, as a prediction rather than a look-around — the hypothesis
predicts four identical `x86-64/` labels; the abort-before-it reading predicts
none:

```
test-aarch64#147   x86-64/ lines=0   assert_no_leak[aarch64/managed_dynarray_field]
test-i386#156      x86-64/ lines=0   assert_no_leak[i386/managed_dynarray_field]
test-riscv32#131   x86-64/ lines=0   assert_no_leak[riscv32/managed_dynarray_field]
test-arm32#150     x86-64/ lines=0   assert_no_leak[arm32/managed_dynarray_field]
```

**Zero, and one distinct cross label per log.** `assert_no_leak.sh` exits 1 on
LEAK (line 65) and the cross assert is first in all four recipes, so make aborts
before the x86-64 assert runs. The reds measured the cross backends.

(Raised by frankA, ruled out by frank-coordinator's abort argument, falsified
here. Worth the four minutes: had it been true, every conclusion above about
cross-backend behaviour would have rested on an x86-64 measurement.)
