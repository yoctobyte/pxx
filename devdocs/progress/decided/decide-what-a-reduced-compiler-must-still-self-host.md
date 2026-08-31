---
track: U
prio: 55
type: decide
blocked-by: []
summary: "RULED 2026-08-31 (owner): a Pascal-reduced compiler must be able to compile the FULL compiler — a bootstrap/seed property, stronger than the self-host the options debated. The first fork was VOID: it turns on a PXX_NO_PASCAL define that DOES NOT EXIST anywhere in the repo outside this ticket. The 14 real defines omit frontends (ada algol basic cfront erlang fortran lolcode nilpy rust whitespace zig) and three targets (aarch64 arm32 i386) — never Pascal and never the x86-64 host — so every buildable configuration CAN self-host and the structural-incapability case cannot arise. Second fork (what a pin gates) narrowed and still open."
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

---

## RULED 2026-08-31 (owner)

> *"a compiler reduced to **pascal** should be able to compile the full
> compiler. dot. not sure why this is even a ticket."*

### The rule

**A Pascal-reduced compiler must be able to compile the FULL compiler.**

Note this is *stronger* than every option debated above, and stronger in a
useful direction. The options argued about whether a configuration must
**self-host** — reproduce *its own* binary. The rule requires the Pascal-reduced
build to produce the **umbrella** binary: it must be a valid **seed**. That is
the property that matters for a project trying to get out from under its FPC
bootstrap, and self-hosting falls out of it as a special case.

### The first fork was VOID, and this is why the ticket felt wrong

`PXX_NO_PASCAL` **does not exist**. Checked at HEAD: it appears nowhere in
`compiler/`, nowhere in any `.pas`/`.inc`/`.sh`/`Makefile`, and only in two
places in the tree — **this ticket**, and `BOARD.html`, which is generated from
it. The fourteen defines that do ship are:

```
frontends  PXX_NO_ADA ALGOL BASIC CFRONT ERLANG FORTRAN LOLCODE NILPY RUST WHITESPACE ZIG
targets    PXX_NO_AARCH64 ARM32 I386
```

Pascal cannot be omitted. Neither can the x86-64 host backend. **Therefore every
configuration that can be built retains both, and every one of them can be asked
to compile `compiler.pas`.** The fork's premise — *"a `PXX_NO_PASCAL` build
cannot compile its own source at all — not 'fails the gate', cannot be asked the
question"* — describes a state unreachable with the defines that exist.

This is *The name is not the thing* with the whole ticket resting on it: an
identifier that reads exactly like the other thirteen, in a list where the other
thirteen are real. Nothing looked wrong from any direction, and the ticket
correctly refused to guess — it just escalated a question that the code had
already answered by never providing the switch. **The residual question for
whoever revives the idea: if a NilPy-only product is genuinely wanted, adding
`PXX_NO_PASCAL` re-opens this fork for real. Do not add that define without
returning here.**

### What is now required, and it is not currently tested

The rule creates a real acceptance criterion that nothing checks today: there is
**no `PXX_NO_*` wiring in `Makefile` or `tools/gate.sh` at all**, so no reduced
configuration is built or gated by anything. Filed as
`feature-a-the-pascal-reduced-build-must-be-able-to-seed-the-full-compiler`.

### Second fork — NARROWED, still open, NOT ruled here

"What does a pin gate across 2^14 configurations" was not addressed by the
ruling and remains the owner's. It is much smaller now: since every
configuration retains Pascal and the host, none of them is *incapable* of
proving anything, so the honest bar is the ticket's own option 3 (reproducible
under the umbrella, plus its own frontends' suites) with the seed property as
the one named extra a pin should check.

**Recommendation, marked as the agent's and not the owner's:** pin gates the
umbrella plus the Pascal-reduced seed build; every other configuration is swept
asynchronously by Track T against the pushed sha. But note the ticket's own
warning, which is still true: **T sweeps zero reduced configurations today**, so
"T sweeps it" is work to file, not a status quo to lean on.

### AMENDMENT, same day (owner) — Pascal is INTRINSIC, and that is why the define cannot exist

> *"a compiler that's reduced to 'C only' should do that. BUT. our PAL layer is
> written in pascal. hence, pascal compilation is intrinsic. yet. if user wants
> a C only compiler, such should be granted."*

The ruling above says `PXX_NO_PASCAL` does not exist. **This says why it cannot**,
which is the stronger and more durable statement — verified at HEAD:

- `lib/rtl/pxxcio.pas` is **Pascal** and implements `__pxx_write`, the function
  `lib/crtl/src/stdio.c` declares `extern` and every C program calls;
- `compiler/builtin/builtinheap.pas` is a **Pascal unit** and is the runtime
  linked into every binary;
- the PAL is `lib/rtl/pal*.pas` — Pascal.

**A C program compiled by pxx links Pascal source that must be compiled.** So
the C frontend cannot function without the Pascal frontend. Omitting Pascal does
not produce a smaller compiler; it produces one that cannot emit a working
program in any language.

### What "C only" therefore means, and it IS grantable

Not "the Pascal frontend is gone". It means **Pascal is not a user-facing input
language**: `.pas` on the command line is refused, while the frontend remains
internally to compile the runtime the user's C program links. That is a product
decision about the CLI surface, not a code-omission define, and it is cheap
precisely because it removes no code.

This closes the residual left open above — *"if a NilPy-only product is genuinely
wanted, adding `PXX_NO_PASCAL` re-opens this fork for real"*. It does not,
because the define cannot be added while the runtime is Pascal. **A NilPy-only or
C-only product is a CLI-surface restriction over a compiler that still contains
the Pascal frontend.** Anyone wanting the define back must first propose a
non-Pascal runtime, which is a different and much larger question.

### Priority (owner, same message)

> *"either way, compiler reduction is low prio and more a feature for low-memory
> targets."*

`feature-a-the-pascal-reduced-build-must-be-able-to-seed-the-full-compiler` and
the parent `feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets`
repriced to **25**. The seed property remains correct and worth having; it is
simply not near-term work, and its value is bounded by how much anyone wants a
low-memory-target build.
