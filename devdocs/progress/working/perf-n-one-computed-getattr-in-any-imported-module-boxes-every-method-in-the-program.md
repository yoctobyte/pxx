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
summary: "`PyModuleHasComputedGetattr` is deliberately COARSE: when it is true, `PyMethodUsedAsValue` returns true for EVERY name, so every method in the program takes the function-object ABI (variant params, variant result) and pays boxing. Until 0c508e507 (2026-09-20 19:23) it scanned the MAIN FILE only, so in practice the coarse arm almost never fired. That commit widened the scan to every Python source range -- required, because a computed getattr in an imported module was a SIGSEGV, rc=139, two fixtures -- and the coarse arm now fires for any program with one computed `getattr` ANYWHERE in its imports. lekkerzeilen has exactly one: `lekkerzeilen/gfx.py:349`, `handle = getattr(self, attr)`. Measured cost on the demo, now CONTROLLED (franks-5b, 5b1045dad, one tree, one CWD, both binaries in-tree, only the compiler differing): code 12047464B -> 12159489B, +112025B, +0.93%, with `procs` IDENTICAL at 11594 -- so no wrappers were added and the growth is boxing inside existing bodies. The uncontrolled estimate filed first landed on these numbers to the byte. SEPARATELY AND DO NOT CONFLATE THE TWO: the same controlled run makes the demo COMPILE 20.3% faster (130.70/130.95s -> 104.15/104.19s, interleaved min-of-N), because the range also contains the memoisation 1fbe6e104. That is BUILD time. THE RUN-TIME COST OF THE BOXING IS STILL UNMEASURED AND IS WHAT THIS TICKET IS ABOUT -- a build-time win does not retire it and must not be quoted as if it had. NOT a correctness bug and NOT a candidate for reverting: the widening is what stops the crash. The question is whether the coarse arm can be narrowed without reopening it, and the honest answer today is that it probably cannot be narrowed by NAME, because a computed getattr is precisely the case where no token spells the name."
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
bound and a direction, not an attribution. *The controlled experiment is one
command and nobody has run it:* build a compiler at `24c2f18de` (the parent;
franks-5b measured its sha as `55f1ef09492b`), compile the demo **from the same
root with the same CWD**, and diff `code=`/`procs=` against HEAD.

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
