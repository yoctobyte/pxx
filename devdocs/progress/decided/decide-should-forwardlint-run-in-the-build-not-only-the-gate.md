---
slug: decide-should-forwardlint-run-in-the-build-not-only-the-gate
track: U
prio: 55
status: open
---

# Should `forwardlint` run in `make compiler/pascal26`, not only in `gate.sh`?

**This is the owner's call because it changes the cost of the most-run command in
the repo**, and the per-fix loop is defined in CLAUDE.md. Filing rather than
deciding.

## What happened

On 2026-08-30 a lane pushed `392782317`, which added `CNodeArrayShape` and called
it ~1000 lines above its body. pxx prescans the unit; **FPC resolves in source
order**, so the bootstrap seed could not compile at all. It sat on origin for
**three commits**. `make compiler/pascal26` stayed green throughout — as it must:
the fixedpoint proves the compiler reproduces *itself*, compiled **with pxx**, and
a missing forward declaration does not disturb that. This is face 31, the seed
canary hole, doing exactly what it is documented to do.

`tools/forwardlint.py` exists precisely for this and exits 1 correctly. It did not
fire because it is wired **only into `gate.sh`** (`tools/gate.sh:221`), and
`gate.sh quick` is *optional* per fix — *"run it when you touched something you're
nervous about."* The lane ran it one commit late, on a different change, and it
caught the earlier break.

The lane's own read, which is fair: a new routine called from a distant include is
exactly the "something you're nervous about" case, so the clause worked as written
and the judgement call went the other way. **A documented trap is not a guard.**

## The fork

**A. Wire it into the `compiler/pascal26` recipe.** Closes the hole by
construction — the one class of breakage the per-fix loop is blind to *by design*
stops leaving anyone's tree.

**B. Leave it in `gate.sh` only** and rely on the optional clause plus Track T's
sweep.

**C. Something narrower** — e.g. run it only when a `.inc` gained a new
`procedure`/`function` since the last build.

## The measurement

`python3 tools/forwardlint.py` = **4.1s**. `make compiler/pascal26` = ~12s. So
option A is ~16s, a **33% increase on the repo's most-run command** — but only on
an actual rebuild, since make skips the target when sources are unchanged, and a
rebuild is exactly when the check is needed.

## Recommendation

**A.** 4 seconds on a command that already costs 12, paid only when sources
changed, against a failure mode that is invisible to the entire per-fix loop by
construction and that poisons the seed for every lane. The asymmetry is the
argument: the loop's own documentation says this hole exists and cannot be closed
from inside it, so the check has to sit outside — and `gate.sh` being optional
means "outside" currently means "sometimes".

The counter-argument deserves stating: eight lanes each paying 4s per rebuild all
night is real, and the owner may prefer C. What should **not** happen is B plus a
stronger warning, which is the option that already failed.

---

## RESOLVED 2026-08-30 — **status quo. It does not join the loop.**

Owner:

> *"this is only about FPC bootstrapping, right? and while 5 seconds doesnt sound
> like much, a thousand times a day is much. we actually did a lot of effort to
> have a very quick self-check (around 40 seconds now or so, if all is well).
> adding 10% to that is significant for something we only have to check every so
> often (on major pinned versions)"*

### The ruling, and the rule behind it

**Gate a property at the boundary where it is consumed.** The FPC seed is
consumed at a cold start and at a pin. That is where it is gated. It does not
belong in a per-edit loop, and no amount of instance-counting changes that,
because the instances are all *between* pins — where nothing consumes the seed.

This supersedes the rule the recommending agent offered ("seconds not minutes,
blind by construction not breadth"). That one is a property of the *check* and
drifts with a stopwatch; this one is a property of the *thing checked*.

### Three things the tickets got wrong, all in the same direction

1. **The status quo already does what the ruling asks, and more.**
   `tools/gate.sh` runs forwardlint before the mode dispatch — every mode, not
   skippable — **and** starts a real `fpc` seed build in the background,
   concurrent with the other steps and skipped when compiler sources are
   untouched. `gate.sh quick` is REQUIRED before a pin. So the seed is checked
   at every pin boundary, by the actual compiler rather than a model of it, at
   near-zero marginal wall time.
2. **Wiring it into `make compiler/pascal26` would have double-charged.**
   `gate.sh quick` runs the build, so the proposal taxes the mandatory pin gate
   as well as every dev rebuild — the one path that already covers this.
3. **The cost figure was stale by 5x.** `gate.sh` documented forwardlint at
   `~1s`; measured 2026-08-30 on plexus, three runs: 5.71 / 5.48 / 5.23s. All
   three tickets inherited the wrong number and argued cheapness from it.
   Corrected in `tools/gate.sh` in the same commit as this resolution.

### The evidence the tickets cited argues the other way

The 2026-08-30 duplicate forward — presented in this ticket as *"the stronger
form of the argument"* — happened because the break was **visible** and two
lanes raced to fix the same absence within 60 seconds, landing two forwards for
one gap. Waiting for the pin would have meant one person fixing it once, with a
tool that names the exact site and the FPC error text.

**Six lanes independently discovering and reacting to a red seed cost more than
the red seed did.** Making it more visible, more often, makes that worse. The
instance count was being read as severity when it was mostly duplication.

### What was NOT disputed

`forwardlint` is a good tool and this changes nothing about it. It stays wired
into `gate.sh` in every mode; it caught both directions of the 2026-08-30 break
(missing forward AND duplicate forward), and it is what made the duplicate a
two-line fix instead of a bisect. The question was only whether it becomes
mandatory per fix, and the answer is no.

### Also fixed, because it is what sent an agent into an unnecessary bootstrap

`Makefile`'s seed-missing message said *"Run: make bootstrap"* — the FPC cold
start, almost never what the reader needs, since the committed stable binary
self-seeds. It now names the self-seed first and `make bootstrap` last, as what
it is.

While rewriting it, one further piece of stale advice was found by measurement:
**the `touch`-after-copy step is no longer needed.** The `$(COMPILER_STAMP)`
mechanism closed the copied-in-seed no-op, so a seed newer than every source
still builds — verified by `cp`ing pinned over the binary, removing the stamp,
and getting `converged after 2 round(s)`. **CLAUDE.md still tells readers to
`touch` the sources after seeding a tree from outside.** That is the owner's
file and is left for the owner; see
[[bug-d-claude-md-still-prescribes-a-touch-the-stamp-fix-made-unnecessary]].
