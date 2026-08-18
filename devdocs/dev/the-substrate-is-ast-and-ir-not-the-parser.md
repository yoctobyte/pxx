# The substrate is the AST and the IR — **not** the parser

Companion to `ir-as-substrate.md`, and the necessary counterweight to it.

`ir-as-substrate.md` says push generality **down** into the core and keep frontends
thin. Read alone, that invites a wrong move: *"then the parser should be shared too."*
It should not. This note draws the line.

## The rule

**Share the AST and the IR. Duplicate the parser, the lexer, and their support
functions, per language.**

> "Language parsing differs enough to duplicate code. Do not try to fit all alternate
> cases into a single support function. What is shared is AST and IR, not the parser."
> — user, 2026-08-18, saying it for at least the third time

Earlier statements of the same rule: 2026-07-20 (runtime helpers — *"as long as our AST
is shared, I don't care for duplicating helpers because of syntax variations"*) and
2026-08-09 (extended explicitly to **parser support functions**).

## Why the line falls exactly there

The IR is the **multiplier**: every backend, every optimization, every target hangs off
it, so it must stay one thing. A parser is **leaf code** — cheap to write, cheap to
duplicate, and cheap to get *exactly* right for one language. Making one parser helper
serve two languages buys nothing and costs correctness in both.

**A shared helper silently couples two specs**, and the coupling is invisible until it
produces a wrong answer. The worked example is `VariantToBool`: shared between Pascal
and NilPy, it acquired **Python** truthiness (`''` false, `0.0` false) and was then used
for Pascal's `b := v`. What looked like a hard semantic decision was not a decision at
all — it was a badly shared helper. The same trap in the parser is worse, because the
divergences are syntactic and endless.

## This does NOT contradict `normalise-dont-special-case.md`

Both are true; they operate on different axes, and confusing them is the failure mode.

| | rule |
| --- | --- |
| **WITHIN one language** | **normalise.** Two shapes reaching one construct (const vs variable, literal vs named receiver) → one path, not two. A second path is the one that stays broken. |
| **ACROSS languages** | **duplicate.** Two languages reaching one construct → two paths. Merging them couples two specs. |

Shorthand: *normalise within a language, duplicate across languages.* A shared token
already means different operators per frontend (`tkSlashEq` is `//=` in NilPy and `/=`
in Pascal), which is the tell that the syntactic layer is not shared ground.

## What this means concretely

- **Do** put it in the shared layer if it is language-neutral: an IR op, an AST node,
  a symbol-table rule, a backend behaviour.
- **Do not** add a mode flag to a shared helper to serve a second language. Copy it and
  make each version exactly right. `pyfloordiv_i`, `pystr_repeat`, `pyvar_*` are the
  pattern.
- **Do not** compromise between two specs. There is no correct midpoint between Python
  raising `TypeError` and Delphi coercing a Variant.
- A gate on "which language am I compiling" inside shared lowering code is a smell —
  it usually means the helper should have been two helpers. See
  `PyProgramMode` being program-wide rather than user-code-wide for what that costs.

## The naming accident this explains

`compiler/parser.inc` was intended as **`pasparser.inc`** — the *Pascal* parser. Its
generic name is a historical accident of Pascal being the seed, not a design decision,
and it is why Track P still cannot be staffed alongside Track A. C and NilPy were both
carved out into their own lexer/parser; Pascal never was.

**Do not read the name as a mandate.** A `commonparser.inc` may hold what is genuinely
neutral, but the default is per-language files, and "make it serve both" is the move
this note exists to refuse. Tracked as
`refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files`.
