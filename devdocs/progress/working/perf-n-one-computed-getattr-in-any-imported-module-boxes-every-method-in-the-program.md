---
slug: perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program
track: N
prio: 45
type: perf
status: working
owner: franks-5b
created: 2026-09-20
found-by: frankb-8e
tags: [nilpy, getattr, abi, boxing, blast-radius, lekkerzeilen]
blocked-by: []
summary: "PARKED 2026-09-22 BY franks-5b, WHO IS STOPPING -- FREE TO TAKE, no handover needed, `owner:` here is ATTRIBUTION not a claim. STATE: the measurement below is COMPLETE and the ticket is NOT blocked. The one piece of work that was planned and NOT done is E4 -- widen the fixture's method-name vector to ~30 equal-length names with the called one LAST, to test whether the 4.01x is variant tag dispatch (my attribution) or a first-wins scan. PREDICTION BANKED BEFORE MEASURING, so it can falsify me: the unboxed arm stays flat and the ratio rises above 4.01x; A FLAT RATIO FALSIFIES MY OWN 'variant tag dispatch' attribution and points at the scan instead. It needs a quiet box -- mine was at load 10.44 with a render running, which is why it was not taken. Nothing else here waits on anything. `PyModuleHasComputedGetattr` is deliberately COARSE: when it is true, `PyMethodUsedAsValue` returns true for EVERY name, so every method in the program takes the function-object ABI (variant params, variant result) and pays boxing. Until 0c508e507 (2026-09-20 19:23) it scanned the MAIN FILE only, so in practice the coarse arm almost never fired. That commit widened the scan to every Python source range -- required, because a computed getattr in an imported module was a SIGSEGV, rc=139, two fixtures -- and the coarse arm now fires for any program with one computed `getattr` ANYWHERE in its imports. lekkerzeilen has exactly one: `lekkerzeilen/gfx.py:349`, `handle = getattr(self, attr)`. Measured cost on the demo, now CONTROLLED (franks-5b, 5b1045dad, one tree, one CWD, both binaries in-tree, only the compiler differing): code 12047464B -> 12159489B, +112025B, +0.93%, with `procs` IDENTICAL at 11594 -- so no wrappers were added and the growth is boxing inside existing bodies. The uncontrolled estimate filed first landed on these numbers to the byte. SEPARATELY AND DO NOT CONFLATE THE TWO: the same controlled run makes the demo COMPILE 20.3% faster (130.70/130.95s -> 104.15/104.19s, interleaved min-of-N), because the range also contains the memoisation 1fbe6e104. That is BUILD time. THE RUN-TIME COST IS MEASURED (franks-5b, 2026-09-22, ON A TREE PREDATING 6d615275a -- that fix adds a zero-init store per managed print() argument temp, which is outside this fixture's hot loop, but the number has not been re-taken since and a re-run is one build) AND IT IS 4.01x ON A METHOD-CALL-DOMINATED SYNTHETIC -- min-of-5 interleaved, boxed 8.69 s against native 2.17 s over 6,000,000 method calls, one define apart from one tree, the ON arm BYTE-IDENTICAL to compiler/pascal26. THE ALLOCATION ROW IS THE INFORMATIVE ONE: seven allocations in BOTH arms, identical, so the 4x is ABI width and variant tag dispatch and NOT the heap -- chasing the allocator would find nothing, and 'make the boxed path cheaper' means dispatch and parameter passing. Code +103,020 B (+25.8%) with procs identical at 2232. CONTROLS: on a program where the arm cannot fire the two compilers emit BYTE-IDENTICAL binaries, so the define is confined to this arm; with the getattr present they differ; both arms print the same answer. READ IT AS A CEILING, NOT AS A PREDICTION FOR THE DEMO -- the fixture's loop is almost nothing but method calls, lekkerzeilen's frame is not, and the demo has still not been run at HEAD. The switch -dPXX_COARSE_GETATTR_OFF is committed and documented at the arm so the price is re-derivable; it is TIMING ONLY and suppresses the crash fix. THE CRASH THAT BLOCKED NARROWING IS FIXED AND THE EDGE IS CUT (frankb-8e, 6d615275a, resolved 05e56ab32, 2026-09-22): bug-a-the-nilpy-print-promo-argument-temp-is-never-zero-initialised is in done/. It was never promo-specific -- every managed print() argument temp was minted unzeroed, because it takes a NAME and so misses every zero-init pass keyed on not having one -- and BOXING WAS MASKING IT, since when this arm fires the promo pair becomes tyVariant and the crash disappears. The first version of the benchmark below segfaulted for exactly that reason. RECORDED BECAUSE IT IS THE REASON THIS TICKET WAS BLOCKED AND NOT BECAUSE IT STILL IS: narrowing this arm would have turned working programs into segfaults, and no longer does. NOT a correctness bug and NOT a candidate for reverting: the widening is what stops the crash. The question is whether the coarse arm can be narrowed without reopening it, and the honest answer today is that it probably cannot be narrowed by NAME, because a computed getattr is precisely the case where no token spells the name."
---

## What it is

Three functions decide whether a method must carry the function-object ABI.
`PyMethodUsedAsValue` is the entry point; it consults
`PyModuleHasComputedGetattr` first, and **that one is an all-or-nothing switch**:

```pascal
if PyModuleHasComputedGetattr then
begin
  Result := True;    { every name, unconditionally }
  Exit;
end;
```

The comment says so and says why: *"A COMPUTED getattr reads a method by a name
no token spells, so the scan below cannot see it... Normalise every method in a
module that does this. Coarse on purpose."*

**The comment says "in a module". The code says "in the program", and before
2026-09-20 those two readings were nearly the same thing** — the scan walked
`1..MainProgramTokCount`, the main file only, so a library or a demo whose
computed `getattr` lived in an imported module simply never tripped it. The
widening in `0c508e507` made the code's reading the operative one.

## Why it is not simply a regression to revert

The widening is the fix for
`bug-n-a-bare-read-of-a-method-as-a-value-yields-a-garbage-code-address`.
A computed `getattr` in an imported module answered False, no method was
normalised, and `pydynattr_get_v`'s bound-method arm then bound `mi^.Code`
through `pybound_new_star` against a native signature. That is not a diagnostic;
it is a jump to a garbage code address. Two committed fixtures,
`rc=139` on pin v413 and `rc=0` at HEAD.

**So the coarse arm is load-bearing and the blast radius is the price of it.**

## The measurement, with its population

    demo        /home/neo/lekkerzeilen, HEAD 25e188f, clean tree
    command     pascal26 --threadsafe -dSDL_DISABLE_IMMINTRIN_H \
                  -dGL_GLEXT_PROTOTYPES lekkerzeilen/__main__.py <out>
    CWD         /home/neo/frankB (repo root)

    before   code=12047464B  procs=11594     bin/build.log, 18:23, compiler 55f1ef09*
    after    code=12159489B  procs=11594     compiler 7e5bea1ba120 at 1fbe6e104

    delta    +112025B code (+0.93%), procs unchanged

CONTROLLED RE-RUN, franks-5b, `5b1045dad` -- one tree, one CWD, both binaries
in-tree under distinct names, `--where | grep -c MISSING` equal on both arms:

                     24c2f18de          HEAD (0c508e507 + 1fbe6e104)
    code=            12,047,464 B       12,159,489 B      (+0.93%)
    procs=               11,594             11,594        identical
    compile              130.70/130.95 s    104.15/104.19 s   (-20.3%)

**The size rows reproduce to the byte.** The compile row is a RANGE of two
commits and is the memoisation, not this ticket's subject: the widening alone
should cost time, so `1fbe6e104` is plausibly worth more than the 26.5 s it
nets. Nobody has separated them and nobody needs to for this ticket.

**THIS COMPARISON IS NOT CONTROLLED AND MUST NOT BE QUOTED AS IF IT WERE.** The
"before" row is another seat's build from another checkout, and the two
compilers differ by ~44 commits, not by mine alone. What it establishes is a
bound and a direction, not an attribution. *The controlled experiment* -- build a compiler at `24c2f18de` (the parent;
franks-5b measured its sha as `55f1ef09492b`), compile the demo from the same
root with the same CWD, and diff `code=`/`procs=` against HEAD -- **has been
run**, by franks-5b at `5b1045dad`, and its numbers are the second table above.
This paragraph said "nobody has run it" while sitting fifteen lines below the
result it was asking for.

`procs` being identical is the informative half: **normalisation did not add
procedures, so the growth is boxing emitted inside bodies that already existed.**
Code size is not run time, and no run-time number has been taken.

## Why narrowing is hard, so nobody spends a day discovering it

The obvious narrowings do not work:

- **By name** — impossible by construction. The whole reason this arm exists is
  that a computed `getattr` names the method at run time; no token spells it.
- **By module** — matching the comment, normalise only methods declared in the
  module that contains the computed `getattr`. **This reopens the crash**:
  `getattr(o, attr)` in module M can fetch a method of a class declared in
  module N, and M cannot know N.
- **By receiver type** — would need the static type of `o` at every computed
  `getattr`, which is exactly what a dynamically typed receiver does not have.

What might work, unexplored: restricting to classes that are *reachable* as a
computed-getattr receiver, which is a reachability analysis nobody has written;
or accepting the boxing and making the boxed path cheaper, which is where the
frame-rate profile already points.

## Where it connects

A 100-sample PC profile of the demo's frame loop the same evening put **~80% of
thread-1 self time in the pxx/NilPy runtime** — variant tag-dispatch,
retain/release, boxing, allocation — with no single site above 15% and only ~15%
in application code. **That profile was taken on the 18:23 binary, i.e. BEFORE
this change.** So the demo the owner is watching does not yet carry this cost,
and a rebuild at HEAD is the first build that will. That makes the controlled
experiment above worth running before anyone re-measures the frame rate, or the
delta will be attributed to whatever else landed.

## What would retire this ticket

Either a measured **run-time** cost small enough to close it as chosen — in
which case say so and record the number — or a narrowing that keeps both
fixtures passing. **The 20.3% build-time win recorded above is not that number
and does not bear on it**; it is the memoisation paying for the widening at
compile time, in a range that contains both commits, and the boxing it leaves in
the emitted code is untouched by it. **Both fixtures must pass: they are the only thing standing between
this arm and a SIGSEGV.**

## BLOCKED-BY WIRED 2026-09-22 (`frankz-e5`, at the ticket owner's request): NARROWING THIS ARM UNMASKS AN -O2 SEGFAULT

**The edge is an ORDERING dependency, not a shared cause, and it points the way
the ranker needs it to point:** narrowing the coarse arm is the whole point of
this ticket, and narrowing it is what exposes
`bug-a-the-nilpy-print-promo-argument-temp-is-never-zero-initialised`
in programs that work today.

`franks-5b`'s measurement, relayed and attributed rather than re-run here: when
the coarse arm fires, every method takes variant params and results, the
`tyPromoInt64` pair disappears into `tyVariant`, **and the crash goes with it.**
Its first benchmark for this ticket ran clean *because* it contained a computed
`getattr`; deleting the getattr is what produced the segfault.

**So whoever takes this ships a narrowing that turns working programs into
SIGSEGVs unless the -O2 bug lands first — and the reds will look like their own
work**, which is the self-blaming reading this fleet has now recorded twice in
one day as the one that terminates a search.

**What this edge does to the ranking, said out loud because I wired it:** this
ticket is already an edge under `umbrella-lekkerzeilen-runs-at-15-fps` (p95), so
the blocker now inherits p95 transitively where its own number is p80. That is
the intended effect and it is the argument for the edge — a crash at the default
`-O` that gates this umbrella's own perf work should not rank below the perf work
it gates.

**What would retire the edge:** the -O2 bug landing, or a measurement showing the
narrowing can be done without un-boxing the promo-int pair. Nothing else.
## 2026-09-22 — the run-time cost, measured: 4.01x, and it is not the heap

The ticket's one open question was the RUN-TIME cost of the boxing. It could
not be asked on lekkerzeilen without the display, which is another seat's, so it
is asked on a CPU-bound synthetic instead — with the caveat that owns the result:
**this measures the fixture, and the fixture's inner loop is almost nothing but
method calls.** Read it as an upper bound for call-dominated code, not as a
prediction for the demo.

### The fixture

`bench_mod.py` holds a three-method class and one computed `getattr` in a
function that is **never called**, so the coarse arm fires while the program
never executes the dynamic path — which is what lets the two arms run the same
program. `bench_main.py` calls all three methods in a 2,000,000-iteration loop.

Both arms are one `-d` apart from one tree; `p26_ga_on` is **byte-identical to
`compiler/pascal26`** (`fda77c48b8ee4b03`), so the ON arm is the shipped
compiler and not a variant of it.

### Controls, before the number

- **The define is confined to the arm.** On a program with no `getattr` at all,
  the two compilers emit **byte-identical binaries** (`cmp` clean). So the
  define does nothing except where the coarse arm can fire.
- **The define fired.** With the `getattr` present the binaries differ.
- **The two arms are the same program.** Both print `999829`.

### The numbers

    interleaved, min-of-5, load 3.08 before / 2.92 after

    boxed  (arm fires)   8.91  8.85  8.96  8.81  8.69   -> min 8.69 s
    native (arm off)     2.25  2.20  2.17  2.24  2.23   -> min 2.17 s
                                                           4.01x

    code    502,733 B  vs  399,713 B     +103,020 B, +25.8%
    procs        2232  vs       2232     identical
    allocs          7  vs          7     IDENTICAL

**The allocation row is the informative one.** 6,000,000 method calls, seven
allocations, the same seven in both arms. The 4x is **not** the heap: it is ABI
width and variant tag dispatch inside bodies that already existed — which is
the same story `procs` being identical tells about the code growth.

That matters for the fix direction. The ticket's own suggestion was "accept the
boxing and make the boxed path cheaper"; this says the target is dispatch and
parameter passing, and that chasing the allocator would find nothing.

**Read the two halves separately, because only one of them is what was asked
for.** The ticket wanted a COST and it got one: 4.01x. It also carried an
unstated MODEL — that boxing means heap traffic — and the same run refutes it.
Six million calls, seven allocations, the same seven in both arms. **A
measurement that confirms the cost and falsifies its assumed mechanism reads as
merely confirmatory unless the second half is pointed at**, and the second half
is the one that decides where the work goes: it eliminates the fix everyone
would have tried first and turns "boxing is slow" into something a great deal
narrower. The negative row is the finding.

### What this does NOT say

It does not say lekkerzeilen is 4x slower. The demo's frame does far more than
call methods, the profile already puts ~80% of thread-1 self time in the runtime
generally, and no one has run the demo at HEAD. **A 4.01x on a fixture whose
loop is only method calls is the ceiling of this effect, and the demo's share of
it is unmeasured.**

### The switch is committed

`-dPXX_COARSE_GETATTR_OFF`, documented at the arm, so the price is re-derivable
without rebuilding the instrument. It is **timing only** — it suppresses the
crash fix, and a program that actually executes a computed `getattr` jumps to a
garbage code address without it.

### A blocker discovered by this fixture, and it gates any narrowing

The first version of this benchmark **segfaulted in the native arm**, and it was
not the arm's fault: `bug-a-the-nilpy-print-promo-argument-temp-is-never-zero-initialised`.
The NilPy `print()` promo argument temp is never zero-initialised and the cleanup
path releases it, on pin v418 and at HEAD. **The frame-shape and `-O2` framings
this ticket originally cited were both retired on 2026-09-22** -- the fault
depends on what the previous frame left on the stack, so it reproduces at every
`-O` level and the local count only chooses which slot inherits which bytes. **Boxing masks it** — when the
coarse arm fires, the promo-int pair becomes `tyVariant` and the crash
disappears. The benchmark above only runs because a fourth local was added to
leave that composition.

**So narrowing this arm will turn working programs into segfaults until that bug
is fixed.** Whoever takes this ticket needs it closed first, or the reds will
look like their own work.

### MY OWN BENCHMARK PINS AN AXIS I DID NOT ENUMERATE — the 4.01x is a FLOOR for the dispatch half, not a measurement of it

Source reading only, 2026-09-22, no box time, **unmeasured and flagged as such**.
Recording it against my own number before someone else finds it.

The boxed call does not merely widen the ABI. It routes through a **run-time
method lookup that the direct call does not have**. `pyparser.inc:16940` names
the chain: the emitted `pydyn_meth<n>(recv, 'name', a0..)` goes to `PyDynMethL`,
which resolves *a declared METHOD first (`PyFindMethCI` + `PyHostCall`), then
`pydynattr_get` for a callable ATTRIBUTE, then AttributeError*. And
`PyFindMethCI` (`compiler/builtin/pyeval.pas:973`) is a **linear scan with a
case-insensitive compare per entry, walking the parent chain, with no cache and
no interning**:

```pascal
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
      for i := 0 to Integer(curr^.MethCount) - 1 do
        if PyEqCI(meths[i].NamePtr^, name) then ...
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
```

O(methods x inheritance depth) per dispatched call.

**WHY THIS DOES NOT CONTRADICT THE ALLOCATION ROW.** `PyEqCI` is explicitly
allocation-free and says so at its own definition — a previous
lowercase-both-then-compare version cost two `PXXStrFromLit` buffers per call
and was removed. So `allocations IDENTICAL at 7` stands, and the lookup is pure
CPU. The two measurements agree.

**WHY THE 4.01x UNDERSTATES THE DISPATCH HALF.** `PyEqCI` rejects on a **length
mismatch before comparing a single character**. My fixture's receiver is a
three-method `Vec` with a shallow hierarchy and distinct-length method names, so
the scan is roughly three integer compares and a hit. **That is the cheapest
value this axis can take, and my benchmark holds it there by construction** —
not by choice, but because a fixture is a minimised artefact and a minimal class
has few methods, short chains, and names that differ. The axis is a property of
the RECEIVER'S CLASS SHAPE, which nothing in the fixture varies and nothing in
the write-up named.

This is CLAUDE.md's "a minimal case pins an axis you did not enumerate" landing
on my own measurement, one section below where I said the cost was ABI width and
tag dispatch. **That attribution may still be right for MY fixture and cannot be
carried to lekkerzeilen**, whose classes are neither three-method nor shallow.

### E4 — vary the receiver's class shape, prediction written first

**Setup:** widen `Vec` from 3 methods to ~30, give them **equal-length names** so
`PyEqCI`'s length short-circuit cannot fire, and put the called method **LAST**
in the table (CLAUDE.md's interesting-element-last rule — first-position is the
arrangement that passes). Hold the loop, the arity and the argument types fixed.
Re-run both arms interleaved, min-of-5.

**PREDICTION:**
1. The **unboxed arm stays flat** — a direct call is statically resolved and
   never enters `PyFindMethCI`.
2. The **boxed arm inflates**, so the ratio rises **above 4.01x**.

**WHAT WOULD FALSIFY IT:** the ratio not moving. That would mean the boxed path
does not reach this lookup at all — in which case my "variant tag dispatch"
attribution is naming something I have not identified, and the mechanism is
unestablished rather than merely unquantified.

**Either outcome is worth the run**, because a ratio that is a function of class
shape cannot be quoted as a single number, which is what this ticket currently
does.

### NOT FILED AS ITS OWN TICKET, DELIBERATELY

No open ticket mentions `PyFindMethCI`'s cost (checked `urgent working
unfinished blocked backlog-nilpy backlog-core low-prio rainy-day`; the only open
hit is a prose aside in the nested-class ticket, and every other hit is in
`done/`). It is **not filed separately because it is unmeasured**, and a perf
ticket whose number is a source reading is the thing this repo files instead of
measuring. It belongs here, where the measurement that would settle it is
already set up.
