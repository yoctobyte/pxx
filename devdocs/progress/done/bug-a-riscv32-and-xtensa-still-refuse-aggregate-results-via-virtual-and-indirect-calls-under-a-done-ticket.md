---
slug: bug-a-riscv32-and-xtensa-still-refuse-aggregate-results-via-virtual-and-indirect-calls-under-a-done-ticket
track: A+S
prio: 50
type: bug
status: done
created: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "riscv32 and xtensa still Error() on an aggregate/frozen-string result returned via a VIRTUAL or INDIRECT call, and the message cites feature-cross-virtual-indirect-hidden-dest — which is in done/. That ticket scoped itself to i386/arm32/aarch64 and those three now implement it; the other two were never in scope and the title says 'cross backends'. Real cost: examples/json/jsondemo.pas builds for i386, arm32 and aarch64 and fails to build for riscv32 and xtensa. Third instance today of a cross-target ticket closing over a subset."
---

# riscv32 and xtensa still refuse aggregate results via virtual/indirect calls, under a ticket marked done

Found by compiling `examples/` across five backends against the x86-64 oracle
(`umbrella-cross-target-codegen-is-correct`, 2026-09-02):

```
jsondemo | i386:ok arm32:ok riscv32:BUILD aarch64:ok xtensa:BUILD
```

Both failures are the same refusal, in `compiler/builtin/pylib.pas`:

```
target riscv32: aggregate/frozen-string result via an indirect call is not yet
supported (feature-cross-virtual-indirect-hidden-dest)
```

Four live `Error()` sites, all still present:

- `ir_codegen_riscv32.inc:3611` (indirect) and `:3808` (virtual)
- `ir_codegen_xtensa.inc:4211` (indirect) and `:4262` (virtual)

and **zero** remaining in `ir_codegen_arm32.inc`, `ir_codegen_aarch64.inc`,
`ir_codegen386.inc`.

## The slug in the message points at `done/`

`devdocs/progress/done/feature-cross-virtual-indirect-hidden-dest.md`,
`status: done`. Read it and it is honest about its scope — *"On i386 / arm32 /
aarch64, a function returning an aggregate ... now errors cleanly"* — it named
three backends and delivered three. Its **title** says "cross backends", and its
error strings are still compiled into the two backends it never covered.

So the instrument that fails here is the SLUG. Someone hitting this error follows
the citation, lands on a ticket marked done, and has to read the whole body to
learn it was about other targets. That is the cheapest possible way to lose a
bug: **the reference is correct about something else.**

## This is the third instance today, and that is the actual finding

Same shape, three times, all found on 2026-09-02:

1. **`bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target`**
   — title says every, fixed four, left xtensa. Cost: `lib/rtl/sysutils.pas`
   itself would not build for xtensa, so no program using sysutils could target
   the ESP ABI. Fixed `7cc404961`.
2. **the concat-ownership fix** — `ir_codegen_xtensa.inc` records it in its own
   words: *"fixed 'the four cross backends' and never listed xtensa — the
   seventh backend that a grep for the common spelling does not return."*
3. **this one** — three of five, and the two left out are riscv32 and xtensa
   again.

**The population is seven backends** (x86-64, i386, arm32, aarch64, riscv32,
xtensa, wasm32). "Cross backends" is not a number and it keeps being read as
"all of them". Whoever fixes this should also consider whether the enumeration
belongs somewhere a grep can find — a list of backends that a fix must tick off
would have caught all three.

## Why prio 50 rather than 45

A real program (`jsondemo`) is unbuildable on two targets, one of which is the
ESP ABI. It is above ordinary cleanup and below a wrong-value bug, and it should
be wired as a blocker of `umbrella-cross-target-codegen-is-correct` — which had
no blockers at all before this sweep, meaning nobody had attempted the cell.

## Gate

`examples/json/jsondemo.pas` must build and match the x86-64 output on all five
cross targets. Note the existing per-target tests did NOT catch this and could
not have: the same lesson as the dynamic-array ticket, whose regression ran on
x86-64 only.

## Bound

HEAD `d49484b18`, compiler `709ec4626a67`. i386/arm32/aarch64 confirmed by
grepping their emitters for the refusal (0 hits) AND by jsondemo building and
running correctly on all three, which is the second source.

## Resolved 2026-09-02 (frankC, Track A) — `a0b9eeb9a`

All four `Error()` sites are gone and every backend now returns an aggregate
through both call shapes. Pre-fix binary `0f1d03315f4e`, post-fix
`174a53388c9b`.

### It was not four line-deletions, and here is why

On both targets the hidden destination's register was ALREADY IN USE by the very
dispatch these two paths need:

| target | destination lives in | what the path also wanted it for |
| --- | --- | --- |
| riscv32 | `t1` | the virtual path read the VMT into `t1` |
| xtensa Call0 | `a8` | indirect loaded the callee there; virtual the VMT |
| xtensa windowed | argument word 0 | — but that SHIFTS SELF from `a10` to `a11` |

The windowed case is the sharp one. Windowed has no register that survives the
call8 rotation, so the destination travels as the implicit first argument word,
which is what xtensa gcc does for a >16-byte struct return. That pushes Self
into `a11`, and the VMT is read from `[Self]` — so reading it from `a10` would
have dispatched **through the destination pointer**. A wild call, not a wrong
value.

The dispatch temp therefore moved in BOTH arms, not only the aggregate one
(riscv32 virtual `t1`->`t0`; xtensa Call0 `a8`->`a9`). Fixing a register
collision only where it currently bites leaves the other spelling live, and that
is the arm that stays broken.

### The gate this ticket specified could not work

It said *"`examples/json/jsondemo.pas` must build and match on all five cross
targets"*. It cannot, on xtensa, for a reason that is not this bug and is
correct: jsondemo calls `ParamStr`, and xtensa refuses that deliberately because
an ESP image has no command line. The demo would have gone on reporting `BUILD`
for the one target whose bug was fixed last. **A gate that cannot pass on the
target you are fixing is not a gate.**

What was used instead: `test/test_cross_virtual_indirect_aggret.pas`, which
already existed and already covered the concept — for i386, arm32 and aarch64
only, which is the same subset the ticket is about. It was EXTENDED rather than
duplicated (a second test for one concept is the second path that stays broken):

- a **nine-argument-word** indirect row. riscv32 passes eight words in registers
  and the destination is not one of them, so nothing below nine reaches the
  overflow arm where the pushed block stays live across the call. The old
  six-word row stops one short there and lands exactly ON the boundary on xtensa
  Call0.
- Makefile rows for riscv32 and xtensa, which had none.

**The new row is AIMED, not assumed.** Perturbing that arm's destination offset
alone (`nArgs+1` -> `nArgs+2`) makes riscv32 DIFFER; reverting restores the
match. Without that check the row would have been a line that ran and proved
nothing.

### Controls

Pre-fix, `test_cross_virtual_indirect_aggret` **PASSES** on x86-64, i386, arm32
and aarch64 and is **REFUSED** on riscv32 and xtensa. Post-fix all six match the
x86-64 oracle. So the test discriminates in both directions rather than merely
going green.

The **indirect** refusal was proven separately, with a program containing no
virtual call at all — in the full test the virtual site fires first and would
have masked whether the second site was ever live. Both cited slugs, both were
live, both are gone.

## The generalisation, which is the part worth keeping

This ticket's own closing paragraph asked whether the enumeration belongs
somewhere a grep can find. It does, and it is now
`tools/refusal_slug_audit_devtest.py`, collected by `tools-devtest`.

It answers the one question a grep cannot: **for every ticket slug cited by a
live refusal in the seven emitters, is that ticket open or closed, and which
backends still carry it.** A slug cited by a live refusal while its ticket sits
in `done/` is the defect — either the ticket closed over a subset, or the
refusal is stale and should have gone with the fix. It cannot tell those apart
and does not try; it says where to look, which is what was missing.

Run against the tree as it was at `a0b9eeb9a^` it prints exactly this ticket:

```
!! feature-cross-virtual-indirect-hidden-dest
     CLOSED in done
     still refused by: riscv32, xtensa
     NOT refused by:   x86-64, i386, arm32, aarch64, wasm32
```

It would have caught all three of today's instances the day each ticket closed.

**The guard is itself guarded.** It reports CLEAN when the tree is clean and
CLEAN when its own pattern has stopped matching, and from the outside those are
the same line — so it carries a `selftest` that runs by default, built from the
real refusal string and the real closed slug rather than a synthetic one, and
asserts the pattern finds it, resolves the ticket as closed, and does NOT fire
on prose that merely mentions a slug. Breaking the pattern makes the selftest
exit 1. That mattered here specifically: the repo's only instance was fixed by
the same commit that added the tool, which is exactly how a guard ends up
permanently unable to fail.

It is deliberately NOT a correctness gate on refusals in general. A refusal is
often the right answer for a target — xtensa's 33 deliberate PAL refusals, or
`ParamStr` above. Those cite no slug and never appear.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b88a74311.
