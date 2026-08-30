---
track: U
prio: 55
type: decide
blocked-by: []
summary: "A reduced build (frontends/targets omitted at compile time) may not be able to compile compiler.pas at all — a NilPy-only compiler has no Pascal frontend. So what does a shipped configuration owe the self-host gate: must it self-host, must it merely be REPRODUCIBLE under the umbrella compiler, or neither? And which of 2^13 configurations does a pin gate? Filed as the second half of an escalation that feature-a-build-a-reduced-compiler asserted had happened and had not."
status: backlog
---

# What must a reduced compiler still self-host?

**Owner decision. Do not guess this** — it sets the acceptance bar for every
configuration [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]
[A p55] ships, and that ticket's own acceptance test is written against an answer
nobody has given.

## Provenance — this ticket exists because a citation covered for it

The parent's section headed **"Escalated, not guessed"** asserted *"Both open
questions are filed to Track U rather than settled here"* and named this slug.
One of the two was filed. This one resolved to no ticket under any name, in any
folder, for eleven days. The sentence claiming nothing was guessed was itself the
unchecked claim, and the wikilink is what made it read as covered — a dangling
link reads as a dependency, not as an absence. (Caught 2026-08-30 by the
`DANGLING-LINK` check in `tools/progress.py`, which is the check that exists for
exactly this; the parent's prose was corrected the same day and the question left
open rather than answered, which was right.)

## The fork

`make compiler/pascal26` is the per-fix gate for the whole repo, and it is the
byte-identical self-host fixedpoint: the compiler compiles its own source and
reproduces its own binary. **A reduced compiler may be structurally incapable of
that.** `compiler.pas` is Pascal, so:

- a `PXX_NO_PASCAL` build (the NilPy-only product this feature was requested for)
  **cannot compile its own source at all** — not "fails the gate", *cannot be
  asked the question*;
- a `pascal-only, host-only` build **can** self-host, and is the parent's own
  named structural test;
- every configuration in between can self-host if and only if it kept the Pascal
  frontend and the host backend.

So "does it pass the gate" is not a property the shipped set shares, and the
gate's meaning has to be decided rather than inherited.

## Options

**1. Every shipped configuration must self-host.**
Strongest claim, and it makes the reproducibility story uniform. It also makes
the flagship product — a small NilPy-for-ESP compiler — **unshippable by
definition**, since it has neither the frontend that reads `compiler.pas` nor the
backend that runs on the host. Rejecting the user's stated payoff to preserve a
property that payoff cannot hold is the wrong trade, but it is the owner's to
make.

**2. Only the umbrella build self-hosts; reduced configurations are gated on
their own test suites.**
Cheapest, and it is roughly what happens today by default. The cost is
[[feature-a-a-refusal-is-a-claim-with-a-date-on-it]] face **190** with extra
rooms: the fixedpoint proves the compiler reproduces *itself*, not that codegen
is unchanged — and a configuration that never self-hosts loses even that. A
reduced build could carry a codegen defect the umbrella's gate structurally
cannot see, because the omission guards changed which arm runs.

**3. Split "self-hosting" from "reproducible", and require the second of
everyone.**
A configuration must be **reproducible**: same sources + same defines, built by
the *umbrella* compiler, yields a byte-identical binary — and must pass its own
frontends' suites. It need not compile `compiler.pas`. This is askable of every
configuration including `PXX_NO_PASCAL`, it keeps a real determinism claim, and
it names honestly what is and is not being proved.
**Recommended**, with one addition: a configuration that *retains* Pascal + host
**must** self-host, because it can, and a capability we decline to exercise is a
capability nobody will notice losing (face 222 — a test that exists, passes
elsewhere, and is unwired to this target leaves a green sweep).

## Second fork, and it is the expensive one: WHAT DOES A PIN GATE?

Thirteen omission defines ship today. That is nominally 2^13 configurations and
the answer cannot be "all of them" — a pin holds the repo-wide lock and every
lane waits through it. Sub-options:

- **umbrella only** (today's behaviour, implicitly);
- **umbrella + a fixed named set** — e.g. `pascal-only`, `no-nilpy`, and the ESP
  product — chosen once and written down;
- **umbrella at pin time; the configuration matrix swept asynchronously by Track
  T** against the pushed sha, exactly as the cross-target matrix is today.

The third is the same shape as the split this repo already made and is the
recommendation, but it only works if T's matrix actually *has* configuration
jobs — which is itself work to file, in T's lane, once the answer is known.
**Do not read "T sweeps it" as a status quo; today T sweeps zero reduced
configurations.**

## What is NOT being asked

Not whether reduced builds are worth doing — that is settled and shipping.
Not the switch spelling — [[decide-reduced-compiler-switch-spelling]], decided.
This is only: what must a configuration *prove* before it counts as shipped,
and where is that proof run.

## Blast radius of leaving it open

The parent ships configurations today under an unstated bar. Every one landed
before this is answered is a configuration whose acceptance criteria were chosen
by whoever landed it, which is the exact condition Track U exists to prevent —
and it will not look unanswered, because thirteen defines already work.
