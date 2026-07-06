# North star: the IR is the substrate — fat core, thin frontends

_Strategy note for anyone (agent or human) picking up the project. Not mechanics
(those are in `parallel-tracks.md` and `../progress/README.md`) — the *why* that
should shape what you choose to work on._

## The one idea

Every frontend the compiler will ever have — Pascal, C, Rust, Zig, whatever we
fancy next — lowers to the **same shared IR** (Track A: `ir*.inc`, `symtab.inc`,
`defs.inc`, the backends, ABI, ELF). That shared core is simultaneously the
project's **one coordination gate** and its **one force multiplier**. Everything
downstream of it is cheap; everything in it is leverage.

## Gate

Track A is the only place two agents can truly collide and the only place the
self-host contract lives. That's why "give an agent Track A" means "major IR work
is in play" and is the single assignment that needs the *no-other-agent-holds-A*
confirmation. Frontends (C/P/R/Z) are mostly disjoint files that merge cleanly;
the core is the shared ground. Guard it accordingly — land only green, self-host
byte-identical, `make stabilize` + `make pin` when a downstream track needs the
new binary.

## Multiplier

Each **language-agnostic** thing you push *into* the IR — a new node, a
calling-convention shape, a managed-value/ARC contract, a cast/promotion rule, a
backend capability — pays off across **every present and future frontend at
once**. Enrich the core one time and a new language becomes, to first order,
*just a parser that emits IR that already exists*. That is what makes "any
language we fancy" realistic rather than a rewrite each time.

## The corollary that should drive ticket choice

Push generality **down** into Track A; keep frontends **thin**. When a frontend
hits a wall, ask which kind of wall it is:

- **"My parser doesn't handle syntax X"** → frontend work (that track's own
  files). Stays local.
- **"The IR can't *express* X"** (a semantic the backends/IR don't model:
  a value category, an ABI shape, a lowering primitive) → **Track A ticket**,
  even if only one frontend needs it today. Resist bolting a one-off into the
  frontend; the next language will want the same primitive.

The ticket system already rewards this: a core-IR ticket that unblocks work
across several frontends inherits their priority via propagation
(`../progress/README.md`), so it auto-floats to the top of the queue. You don't
have to hand-rank IR work high — make the dependency edges honest and it ranks
itself.

## The flywheel

Thin frontend hits an IR gap → file it as Track A → fix raises the whole floor →
more frontends become cheap → more parallel work can start → each new frontend
exercises the IR and surfaces the next gap. The better the core, the more "funny
parallel works" (new languages, new targets) can run at once without touching
each other. Invest there first.
