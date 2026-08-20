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

## The boundary: what is shared, and what emphatically is not

"Fat core, thin frontends" is about the **IR**, not about the front half of a
frontend. State it precisely, because it has been misread more than once:

> **The shared surface is the AST and the IR tables. Lexers and parsers are
> per language target.** They share code only where sharing is *sane*, and are
> otherwise **free to diverge and re-implement**. A frontend does whatever fits
> its language and meets the AST/IR contract.

So a lexer or parser that re-implements something another frontend already has
is **not duplication to be cleaned up** — it is the design. The thing to push
into the core is a *language-agnostic capability* (an AST node, an IR op, an
ABI or ARC rule). Grammar is not that.

### The failure mode this exists to prevent

The recurring bug shape is a frontend routing through **another language's**
lexer/parser, inheriting a rule that means something different there, and then
accumulating workarounds instead of diverging. Measured instances:

- **`x is K(2)` (2026-08-03).** Pascal's `E is TClass` **type test** lives in the
  shared `ParseExpr` with no `PyExprMode` gate, so it claimed NilPy's identity
  `is`. The construction on the right never ran and the expression answered
  `True` — silent, and invisible to a boolean-only test, since `X() is Y()` is
  `False` either way.
- **`//=` vs `/=` .** One `tkSlashEq` token, two different operators (Python
  floor-divide-assign, Pascal/C divide-assign); a shared parser tail mapping it
  silently broke one frontend.
- **`.5` / `5.` (2026-08-03).** The ticket assumed the fix belonged in the
  shared `lexer.inc` behind a new NilPy mode, with the Pascal frontend in the
  blast radius. NilPy does not lex there at all — it has `pylexer.inc`, and the
  fix was ~20 lines in its own file with Pascal provably untouched.

Each was cheap once diagnosed and expensive to diagnose, because the symptom
appears in the *guest* language while the cause sits in the *host's* rule.

### Where the frontends actually stand

- **C** (`clexer`/`cparser`/`cpreproc`) and **NilPy**'s LEXER (`pylexer.inc`) are
  carved out — the intended shape.
- **NilPy's PARSER** still enters Pascal's `ParseExpr` for expression atoms, and
  **Pascal** has no `plexer`/`pparser` at all (it was the seed, so it still lives
  in the shared `lexer.inc`).

Both of those are **legacy accidents, not the design.** When the choice is open,
prefer re-implementing in the frontend's own file over adding another
`PyExprMode`-style branch to the shared parser. A `PyExprMode` gate is a stopgap
that buys correctness today; it is not the destination.

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
