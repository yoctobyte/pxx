---
track: U
prio: 0
type: decide
blocked-by: []
summary: "REJECTED 2026-08-31 (owner): neither A nor B. The premise is wrong. Measured the same day: the compiler parses its OWN 235,854 lines at ~12,000 lines/sec, and pylib+pyeval's 25,551 lines at ~11,600 lines/sec — the SAME RATE. There is no NilPy runtime tax; there is a general compiler throughput figure applied to 24,000 lines, reframed as a per-frontend pathology. A cache would also be invalid for the population that compiles most often (developers rebuild the compiler every fix, invalidating any compiler-keyed cache on every loop) and its failure mode is an intermittent machine-dependent wrong answer. Superseded by perf-a-the-compiler-parses-at-12k-lines-per-second-find-out-why."
---

# Serialise the compiled unit image, or defer the bodies?

- **Type:** decide (Track U). Raised 2026-08-30 by frankA while surveying
  [[perf-a-cache-the-compiled-nilpy-runtime-unit-image]] [A p60] **before**
  writing code, because the survey changed the risk enough to be worth a
  decision rather than a guess.
- **Nothing is blocked on this today** — it decides which of two projects gets
  built, and both are large enough that starting the wrong one is the expensive
  mistake.

## The cost being attacked

Measured at HEAD `eb3b0fd5c642`, loadavg 2.76:

| | |
| --- | --- |
| zero-byte `.npy` | 2.39 / 2.51 / 2.42 s |
| `begin end.` (Pascal) | 0.21 s |
| **fixed NilPy tax** | **~2.2 s per compile** |

Every `.npy` compile parses `pylib.pas` (18,768 lines) + `pyeval.pas` (5,692)
before looking at the user's program, from an unguarded injection at
`pyparser.inc:34707-34708`. At 719 NilPy jobs per full tier that is roughly
**1,600 CPU-seconds a tier**, plus the same 2.2s on every NilPy user's
hello-world.

## Option A — serialise the compiled unit image (what the ticket assumes)

Persist the compiled result and load-and-relocate instead of re-parsing.

**Cost, counted rather than estimated.** The design names "`Code[]`, `Procs`,
`Syms`, `UCls`, the fixup and RTTI tables" — five things. They are not five. The
capacity growers resize **100** proc-indexed arrays, **44** sym-indexed and
**32** field-indexed: **176 parallel arrays**, before `Code[]`, the string pool,
RTTI and fixups. `defs.inc` declares **242** `array of` globals.

**The standing hazard.** Every one must be serialised, and every array added by
any future Track A commit must be added to the serialiser or the cache silently
emits stale code. This repo has a **named failure class** for precisely this —
`symtab.inc:3932`, *"the 'one of six parallel arrays not written' class this
file's SymTR comment names"* — with a measured instance: twelve symbols carried
an immediate pointee over depth 0 because only nine of twenty-one write sites
touched the whole tuple. A unit-image serialiser makes that class permanent and
puts it at the widest blast radius in the compiler: not a wrong value in one
program, but a compiler that compiled something else.

**What would make it acceptable.** Not review, and not the single-program
`same key => same bytes` check the ticket currently implies — that passes a
serialiser which forgot 170 of the 176. It needs **cold-vs-cached byte-identity
over a corpus**, because a missed array is observable only if some program's
output depends on it. Track T's **719 NilPy jobs** are that corpus and are the
only coverage instrument I would trust here.

**Upside:** helps unconditionally, whatever the user's program uses.

## Option B — defer routine bodies, parse only what is reached

Do not persist anything. Record each routine body's token range at parse time and
parse a body only when something reaches it.

**Why it is idiomatic here and not speculative:** the generic path already has
the primitive. `GenericMethodBodyEnd` computes a body's token extent and
`AppendTokenRangeToTemplateArena` buffers it for later parsing
(`pasparser_generic.inc`). What does not exist is any body-skipping in the normal
unit path (grepped; no hits) — so this is new work, but not a new idea.

**Upside:** persists nothing, so it has **no staleness class and no 176-entry
checklist**, ever. It also helps every large unit, not only NilPy — the same tax
is paid by `uses pylib` from plain Pascal (2.1s measured previously).

**Risk / unknown:** it only pays if most bodies are unreachable, and **that is
unmeasured**. It also does not help the parse of interface sections, which is
part of the 24,460 lines. If a typical `.npy` reaches most of `pylib`, this buys
little.

## The decision, and the cheap thing that informs it

**Recommendation: measure B's ceiling before committing to A.** One number
decides it — the fraction of `pylib`+`pyeval` routine bodies actually reached by
a representative `.npy`. `--dce-report` already exists and DCE already drops
unreachable routines *after* they are parsed, so the reachable-body count is
obtainable today without building anything.

- If most bodies are unreachable, **B** is the better project: comparable win,
  no permanent staleness class, wider benefit.
- If most are reached, **B**'s ceiling is low and **A** is the only route — and
  then A must land with the corpus-wide cold-vs-warm gate from the start, not as
  a follow-up.

Doing that measurement is small and is worth doing whichever way this goes. What
should **not** happen is 176 arrays of serialiser being written on the assumption
that A is the only option, which is what the parent ticket's wording invites.

## MEASURED, same session — B's ceiling is real, not marginal

`--dce-report` is **off for the NilPy frontend** (*"only the Pascal frontend is
wired up so far"*), so this went through the Pascal path, which pays the same tax
via an explicit `uses`:

| program | bodies | live | dead | dead by count | dead by emitted size |
| --- | ---: | ---: | ---: | ---: | ---: |
| `uses pylib` | 1261 | 382 | 878 | **69.6%** | 66.2% |
| `uses pylib, pyeval` (what a `.npy` injects) | 1654 | 653 | 998 | **60.3%** | 40.4% |

**About 60% of the injected runtime's routine bodies are never reached** in the
full configuration. That is B's ceiling and it is substantial.

**Three honest qualifications, because the number is more attractive than it is
precise:**

1. **Count is not time.** Live bodies are *larger* on average — 653 live bodies
   carry 749,377 B against 998 dead ones at 509,775 B — so dead is 60% by count
   but only 40% by emitted size. Parse cost tracks *source* size, which I did not
   measure per body, so 60% is an upper bound on bodies skipped, **not** a
   predicted 60% time saving.
2. **This is a program that does nothing.** A real `.npy` reaches more. The
   figure is the ceiling for the best case, not the typical case.
3. **It does not touch interface parsing**, which is part of the 24,460 lines and
   which B cannot avoid.

**So the recommendation firms up to B-first**: a route with no staleness class
and a ~60%-of-bodies ceiling is worth prototyping before committing to a
176-array serialiser that must be maintained forever. If a prototype shows the
real saving is small — because interfaces dominate, or because typical programs
reach most bodies — that is a cheap negative, and A is still there.

Still a **decision**, not a conclusion: A is unconditional and B is not, and
choosing to bank a permanent maintenance hazard for an unconditional win is
exactly the sort of trade that should be made deliberately by the owner.

---

## Measured arm: what B is actually worth (2026-08-30)

Prototyped as a **measurement, not an implementation** — no compiler change was
made and none is proposed here. The ceiling for "defer every routine body" was
obtained by removing the bodies from the runtime source itself: each of the 863
column-0 `begin`/`end;` pairs in `pylib.pas` and 170 in `pyeval.pas` replaced by
`begin end;`. Declarations, interfaces and unit structure untouched.

That the substitution is faithful to B's *shape* is checkable rather than
assumed: both configurations report **`procs=1859`**, identical. Every symbol
still registers; only bodies vanish. Emitted code goes 1,253,550 B → 370,983 B.

Binary `eb3b0fd5c642` at `f036624b4`. Load average was 15.6-15.9 throughout — far
above the 2.76 of the earlier baseline in this ticket — so **the numbers below
were re-measured interleaved (full, then stripped, then full…) and only the
within-sweep differences are meaningful.** The absolute times are not comparable
to the figures higher up this page.

| configuration | n | median | min-max |
| --- | ---: | ---: | --- |
| zero-byte `.npy`, full runtime | 8 | **2.78s** | 2.69-3.03 |
| zero-byte `.npy`, all bodies stripped | 8 | **1.15s** | 1.06-1.32 |
| `x=1; print(x)`, full runtime | 8 | 2.81s | 2.44-3.54 |
| `x=1; print(x)`, all bodies stripped | 8 | 1.15s | 1.03-1.31 |
| Pascal `program p; begin end.` (no pylib at all) | 3 | 0.37s | 0.31-0.40 |

**The decomposition of a 2.78s compile of a program that does nothing:**

| component | cost | who can remove it |
| --- | ---: | --- |
| routine bodies (parse + lower + emit) | **1.63s** (59%) | B, partially — only the dead ones |
| declaration/interface parsing of the runtime | **0.78s** (28%) | **A only** |
| fixed compiler floor | 0.37s (13%) | neither |

**This inverts the recommendation this ticket closed with.** B's *entire
ceiling* — deferring every body, including the ones the program needs — is
1.63s, and B can only claim the dead share of it. Scaling by the 60.3% dead-body
figure measured above gives **≈0.98s, about 35%**, and that is optimistic for the
reason qualification 1 already gave: dead bodies are the *smaller* ones (60% by
count, 40% by emitted size), so the true figure sits below it. A, by removing
bodies and declarations together, has a ceiling of **2.41s (87%)** — A's
realistic reach is roughly twice B's ceiling and nearly three times B's likely
value.

**One term is measured and one is not.** Replacing the bodies with comment text
of the same byte volume (837,857 B vs the original 807,791 B) costs 0.97-1.05s
against the stripped 0.96-1.04s: **the body text's byte-scan cost is ~0.02s**, so
the 1.63s is parse+lower+emit and not I/O. What that experiment does *not* cover
is **tokenisation** — pxx lexes the whole file into `Tokens[]` up front, and a
real B would still build those tokens before skipping them, whereas both the
stripped and commented variants avoid it (comments never become tokens). So B's
real saving is `1.63s × dead-share − tokenisation`, and only the subtrahend is
unmeasured. It can only make B worse.

**What this does and does not settle.** It does not retire B: no staleness class
is still a real property, and 35% of a 2.8s tax is not nothing. It does remove
the argument that carried the earlier recommendation — that B should be tried
*first* because its ceiling was large enough to make A's 176-array maintenance
hazard avoidable. The 28% declaration-parsing band is invisible to B by
construction, and it is the band that makes A unconditional. **Recommendation
revised to A-first**, with the same caveat as before: it is the owner's call, and
A's cost is a serialiser over 176 parallel arrays that must be maintained
forever — see the gate note above (single-program byte-identity would pass a
serialiser that forgot 170 of the 176; the corpus-wide cold-vs-cached run over
T's 719 NilPy jobs is the real gate).

Method note: the timing harness asserts each compile printed `ok:` and captures
`$?` immediately, after frankC and frank-coordinator found gates reporting exit 0
because a `tail`/`echo` ran last. A compile that fails reports a beautifully fast
time, which is the same failure shape.

---

## REJECTED 2026-08-31 (owner) — neither A nor B; the premise does not survive one measurement

### The measurement

| | lines | time | rate |
| --- | ---: | ---: | ---: |
| `compiler/*.inc` + `compiler.pas` (self-compile, pinned) | 235,854 | 19.7s | **~12,000 lines/s** |
| `pylib.pas` + `pyeval.pas` | 25,551 | 2.2s | **~11,600 lines/s** |

**Those are the same rate.** There is no "NilPy fixed tax". There is a general
compiler throughput number, applied to 24,000 lines of Pascal, that this ticket
and its parent framed as a NilPy-specific pathology and then proposed to route
around with a cache.

(Load caveat, stated because it cuts the right way: the 2.2s was measured by
frankA at loadavg 2.76 on 2026-08-30; the 19.7s was measured on this box on
2026-08-31 under unknown load. If the later measurement was the more loaded one
its 12,000 is a floor, and the two rates agree even more closely.)

### The owner's reasoning, which stands independently of that number

> *"the first best time our cache not matches reality, we waste more time fixing
> that. if any, we should try to reduce those 2.2 seconds since 2.2 seconds for
> 24000 lines may or may not be reasonable. i still don't see the issue, apart
> speeding up testing. in general, i dont like the presumption."*

Three separate objections, all correct:

1. **The cost/benefit of a cache miss is inverted.** A wrong cache does not fail
   loudly; it compiles something else. That bug is intermittent and
   machine-dependent — the most expensive shape this repo has — and one instance
   costs more than every second the cache ever saved.
2. **The population that compiles most often gets nothing.** A developer
   rebuilds the compiler on every fix (the mandatory `make compiler/pascal26`
   loop). Any cache must be keyed on the compiler binary or it emits code built
   by yesterday's compiler — so it is cold on *every* compile of the loop it
   would most like to speed up. This was never addressed by either option.
3. **The right target is the 2.2 seconds itself**, not a way to avoid paying it.

### What the ticket got right, and where its argument actually lands

The only real cost is **the test fleet**: 719 NilPy jobs per full tier each
re-parsing the same two files. That is worth something, since CLAUDE.md makes
sweep rate the binding constraint on how fast a regression is localised. But it
is *also* fixed by making the compiler faster, without a cache, without 176
parallel arrays, and without a new failure class — and that fix helps every
frontend, every compile and every agent's 12-second loop instead of one tier of
one suite.

The counted work in this ticket is still good and is why the rejection is cheap
to trust: 176 parallel arrays behind a five-item design sketch, and the
observation that single-program byte-identity would pass a serialiser that
forgot 170 of them. That analysis killed A on its own terms before the
throughput number killed the whole question.

### Also closed by this

`unfinished/perf-a-cache-the-compiled-nilpy-runtime-unit-image` — the parent that
assumed caching. Nothing in it survives; it should not be picked up.

### Superseded by

`perf-a-the-compiler-parses-at-12k-lines-per-second-find-out-why` — profiling,
no new mechanism, broad payoff.

### The generated-serialiser idea, recorded so it is not re-derived

While ruling, it was established that all **257** `array of` globals in
`defs.inc` are the uniform one-line form and 247 are plain scalars, so the
serialiser could have been *generated* from the declarations, which would have
made "a future commit adds an array and the serialiser forgets it" structurally
impossible. **That is a sound answer to A's objection and it does not matter**,
because the question it answers is not worth asking. Recorded only so that a
future reader who rediscovers it does not mistake it for a reason to reopen this.
