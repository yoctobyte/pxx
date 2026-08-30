---
prio: 60
track: U
status: backlog
owner: unassigned
---

# decide: should `forwardlint` join the mandatory per-fix loop?

## The fork

The FPC bootstrap seed has been broken on `master` **twice in one session**
(2026-08-30), by two different commits in two different lanes:

| commit | lane | missing forward |
| --- | --- | --- |
| `5c8de9442` | A | `CModuleOfTok` (fixed by `e1fed35b1`) |
| `3ee9a672f` | P | `QualArgAliasName`, `EmitQualAliasDecl` (fixed this session) |

Each left every lane's bootstrap red until someone happened to run
`tools/gate.sh quick`. Neither author did anything wrong by the documented loop.

## Why the per-fix loop cannot catch this, structurally

CLAUDE.md's loop is `make compiler/pascal26` + your repro, and it is emphatic
that this IS the byte-identical self-host fixedpoint. It is — and that is exactly
why it is blind here: **it self-hosts with the CURRENT binary and never asks FPC
anything.** pxx resolves across the unit, FPC resolves in source order, so a
call-above-body compiles, self-hosts, converges, and passes the whole documented
gate while the seed is dead. There is no error to wait for, which is the same
shape as the copied-in-seed no-op the loop already warns about.

`tools/forwardlint.py` catches it exactly, is **~5 seconds** (measured as step 2
of `gate.sh quick`, which reported `5s` next to a `91s` fixedpoint), needs no
build, and has no false positives in this repo's history that I can find — the
one apparent FP this session (`CBlockContinues`) was a real break already fixed
upstream between my two runs.

## Options

1. **Add `forwardlint` to the mandatory per-fix loop** for any `compiler/**`
   edit. +5s on a ~12s loop. Recommended.
2. **A PreToolUse/PostToolUse hook** that runs it after an edit under
   `compiler/**` — the `a-documented-trap-is-not-a-guard` shape: make the mistake
   unexpressible rather than documented. Strongest, but hooks are repo-wide
   policy and this repo already gates edits with `no-full-suite.sh`, so the
   precedent exists.
3. **Leave it in `gate.sh quick`** and rely on agents choosing to run quick after
   touching a frontend include. This is the status quo, and it is what produced
   two breaks in one day.

## Recommendation

**Option 1, and option 2 if the user wants it enforced rather than advised.**
The cost is 5 seconds against a break that is fleet-wide, silent, and blocks the
bootstrap for every lane including a fresh clone. Option 3 has now been measured
twice and lost twice.

Filed by frankA rather than acted on: the per-fix loop is CLAUDE.md's single
source of truth for gating, so widening it is a user decision, not an agent's.

## Update, same day: it broke a SECOND time, in the opposite direction

After the fix above landed, two lanes had fixed the same absence independently
and both landed, leaving the pair forward-declared twice. FPC rejects a repeated
forward as hard as a missing one:

```
pasparser_generic.inc(431,10) Error: Function is already declared Public/Forward
  "QualArgAliasName(const AnsiString):AnsiString;"
```

**This is the stronger form of the argument above.** It is not "the seed can
break". It is: **the seed breaks in two opposite ways — a missing forward and a
duplicate forward — and pxx tolerates both, so `make compiler/pascal26`
converges through either.** The self-host loop cannot see this class in either
direction, by construction.

`forwardlint` detects both, and names the *other* declaration site and the exact
FPC error text, which is what made the duplicate a two-line fix rather than a
bisect.

Instance count is now six across six lanes: Track R, frankwasm x2, frankC x2,
Track P (absence), and Track P again (duplicate).

**One further data point for option 2 (a hook) over option 1 (a documented
step).** One of the lanes that broke it *did* run `forwardlint` on the change —
and redirected its output to `/dev/null`, reading the `echo` after it. The tool
told it, at the right moment, in its own terminal, and the answer was discarded.
A documented step survives that; a hook that fails the edit does not.

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
