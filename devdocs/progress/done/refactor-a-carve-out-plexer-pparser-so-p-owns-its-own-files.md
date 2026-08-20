---
track: A
prio: 60
type: refactor
owner: claude-acp
blocked-by: []
summary: "parser.inc is 38% of all compiler work (216 of 566 commits in 14 days) and is the ONE file where two lanes must serialize — A and P cannot edit it concurrently. C and NilPy both got carved out into their own lexer/parser; Pascal never did, purely because it was the seed. CLAUDE.md has called this 'the clean long-term shape' in prose for months, where ready/next cannot see it. Prio is a PROPOSAL: the payoff is parallelism, not a feature."
status: done
---

# Carve out `plexer` / `pparser` so Track P owns its own files

## The measurement that forced this ticket (2026-08-18, last 14 days)

566 commits touched `compiler/`. By file:

| file | commits | lane cost |
| --- | --- | --- |
| `pyparser.inc` | 259 | **none** — N owns it outright |
| **`parser.inc`** | **216** | **A and P must serialize** |
| `pylib.pas` | 155 | N/B |
| `defs.inc` | 59 | shared |
| `ir.inc` | 47 | A |

**The busiest file in the repo costs nobody anything, and the second busiest
serializes two lanes** — and the only difference between them is that NilPy got
carved out and Pascal did not.

## The finding underneath it: the IR is settled, the bottleneck moved

The lane discipline was built when the IR and AST were being actively extended, so
"everything routes through Track A" was correct. That is no longer what the commits
say. Of 82 `ir*.inc` commits in the same window, essentially all are **bug fixes to
lowerings inside a stable design** — `Include/Exclude lowering never assigned Result`,
`a default argument was passed by value`, `a for loop evaluates its limit once`,
`a struct assignment ran its RHS twice`. Almost none add an IR op or change the IR's
shape. New frontend features now **compose from existing ops**, which is the
`ir-as-substrate` bet paying off.

**So the reason to keep strict serialization is no longer the IR — it is
`parser.inc`.** The hazard did not shrink; it migrated, and it migrated to the file
with the highest churn in the whole compiler.

## Why it was never filed

`CLAUDE.md` states the desired end state in prose: *"The clean long-term shape is to
split out `plexer`/`pparser` so P owns files like C/Z do."* Prose in a guide is not a
queue entry — `ready`/`next` read `track:` and `prio:`, nothing else. So the single
highest-leverage structural item in the repo has been correctly diagnosed, written
down, and invisible, for months. Fourth instance in one day of
`feedback_measuring_a_thing_is_not_filing_it`; this is the most expensive.

## What "done" means

- Pascal-facing lexing/parsing lives in `plexer.inc` / `pparser.inc`, owned by Track P.
- `parser.inc` retains only what is genuinely shared across frontends, owned by A.
- **A and P can be staffed concurrently** without the coordinator holding a slot —
  which is the actual deliverable. Everything else is a means to it.
- C's carve-out is the worked precedent; NilPy's is the second. Follow whichever seam
  those two agree on rather than inventing a third.

## Risks, stated plainly

- **Large diff in the file with the highest churn.** It will conflict with anything
  in flight, so it wants a quiet A/P window, not a busy one.
- The gate is unforgiving and that is the point: `make compiler/pascal26` IS the
  byte-identical self-host fixedpoint, so a botched carve-out cannot leave the tree.
- **Token/node numbering discipline** is the known landmine class here — the thing the
  lane rules exist to protect.
- This is a refactor with **no user-visible payoff**. Its return is coordination
  throughput, which is real but only cashes out when two agents actually run on A and
  P at once.

## Prio is a proposal, not a decision

Filed at 60 to sit at the top of Track A's ready queue, on the argument that it
multiplies every future P and A ticket. But it buys **parallelism, not features**, and
whether that outranks shipping work is the user's call — reranking it down is a
legitimate answer, not a mistake.

## SHARPENED by the user, 2026-08-18 — this is a naming accident, not an extraction

The framing above ("retain only what is genuinely shared across frontends") understates
it and points at the wrong shape. The user's correction:

> `parser.inc` **was intended as `pasparser.inc`**. There could be a `commonparser.inc`.
> But on more than one occasion I had to say — language parsing differs enough to
> duplicate code. Do not try to fit all alternate cases into a single support function.
> **What is shared is AST and IR, not the parser.**

So the target is **not** "factor out the common parser". It is:

1. `parser.inc` → **`pasparser.inc`**, owned by Track P. The generic name is an
   accident of Pascal being the seed; it has been read as a mandate ever since.
2. `commonparser.inc` may exist for what is **genuinely** language-neutral — and the
   default is per-language files, not that file.
3. **Explicitly refused: a universal support layer.** "Make this helper serve both
   languages" is the move this refactor exists to prevent, not the method by which it
   is carried out. A shared parser helper couples two specs and is then wrong in both —
   the worked example is `VariantToBool` acquiring Python truthiness and being used for
   Pascal's `b := v`.

Now written up as a standing principle in
**`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`** and linked from
`CLAUDE.md`, because the rule had been stated at least three times (2026-07-20,
2026-08-09, 2026-08-18) and existed in the repo only as one passing clause in
`name-resolution.md`. Having to repeat a design rule is itself the bug.

**Consequence for whoever takes this:** measure the split by *what Pascal alone needs*,
not by what looks factorable. Two similar-looking routines in `pasparser.inc` and
`pyparser.inc` are the intended end state, not debt to be cleaned up later.

## The rename alone is only half the fix — it must also SPLIT

`parser.inc` is **36,217 lines** (measured 2026-08-18; `pyparser.inc` 34,374; the whole
compiler is 58 files / 169k lines with exactly one subdirectory).

Renaming to `pasparser.inc` fixes **ownership**. It does not fix **contention**: A and P
would still serialize, because the lane rule keys on files and there would still be one
file. **Granularity is what buys parallelism** — split into per-area units (declarations,
statements, expressions, types, classes, generics, units, directives) and the lanes
collide only when genuinely working the same area.

Second reason, independent of concurrency: a 36k-line file is where *"one concept, N
independent sites"* bugs are born — you cannot see that the sibling path exists, so you
write a second one. That shape dominates this repo's bug history.

**Method, given the known hazard:** this is a single-pass compiler where include ORDER is
load-bearing and a header missing `forward;` nests every later routine. So slice by slice,
with `make compiler/pascal26` (the byte-identical fixedpoint) as the gate after each —
never one big move. Rationale in
`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`.

## It now gates a shipping configuration (added 2026-08-19)

This was structural debt with no deadline. It is now a **blocker**: the reduced-compiler
work ([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]) can
omit any of thirteen frontends and targets, but it cannot build the **NilPy-only**
compiler the owner asked for — "the python compiler for esp at reduced code size" —
because omitting the Pascal frontend means omitting the shared `parser.inc`, which is
also where the NilPy frontend's 174 forward declarations and much of its behaviour
live. There is no define that can express it; only this carve-out can.

Measured alongside: `pyparser.inc` is 35,682 lines and `PXX_NO_NILPY` costs ~198
symbols, so the *other* direction (Pascal-only, NilPy omitted) is a define and is in
progress. The asymmetry is the carve-out's whole subject — P shares its files with A,
and N does not.

---

## Done — 2026-08-20

`parser.inc` went from **37,249 lines to 109**, in fourteen contiguous slices,
and the residue was renamed `frontend_forwards.inc` because what is left is
cross-frontend forward declarations, not a Pascal parser.

### The method, and why it made the gate a proof rather than a review

Every slice is a **contiguous range of the original, re-included from
compiler.pas in the exact position it occupied**. That is not a stylistic
choice: a contiguous cut restored at its own offset is identical *by
construction*, so the byte-identical self-host fixedpoint can prove the move.
It did — **emitted code size stayed at 8655567B across all fourteen cuts**, and
the fixedpoint converged after every one. The ticket asked for slice-by-slice
gating because include order is load-bearing; this is the shape that makes the
gate answer the question rather than merely not object.

### Where it went

Track P (the Pascal frontend, in include order): `pasparser_name` ·
`pasparser_class` · `pasparser_generic` · `pasparser_call` · `pasparser_lval` ·
`pasparser_expr` · `pasparser_stmt` · `pasparser_decl` · `pasparser_proc` ·
`pasparser_prog`.

Track N: **`pyforwards.inc`** — ~200 `Py*` forwards plus `ParseArgExpr`, the
hook that sends a NilPy call argument down the *Python* precedence chain. This
is the ticket's shipping blocker made concrete: omitting the Pascal frontend
meant omitting `parser.inc`, which is where the NilPy frontend declared itself.

Track A — machinery that was never Pascal and had no business in a frontend's
file: **`ast_arena.inc`** (AllocNode/CloneAST — the substrate every frontend
shares), **`inline_expand.inc`** (an AST pass; also Track O),
**`ast_syminfer.inc`** (symbol typing, stack layout, DWARF var snapshot),
**`dbg_filetable.inc`** (which file a token came from — it maps C translation
units too).

The map lives in the closing comment of `compiler/frontend_forwards.inc`.

### On the rename

The ticket says `parser.inc` → `pasparser.inc`. After the split that name would
have been **wrong**: the 109-line residue holds the C frontend's forwards, the
per-arch emitter dispatchers and path helpers — it is not Pascal. It is
`frontend_forwards.inc`, which serves the ticket's actual intent (kill the
generic name that reads as a mandate) more honestly than the literal one would.

### Two things found on the way

1. **A nested `{$I}` was silently dropped, not expanded** — filed and fixed as
   [[bug-a-a-nested-include-is-silently-dropped]]. The first slice was included
   from `parser.inc` and simply did not appear: `ExpandIncludes` ran one level
   deep and the leftover directive was skipped by the lexer as unknown, so a
   *different program compiled than FPC builds from the same source*. Never seen
   because **no `.inc` in the compiler included another `.inc`** — 58 files, and
   the shape had never been exercised in-tree.
2. **The bootstrap constraint that follows from it.** `make compiler/pascal26`
   compiles `compiler.pas` with the **pinned** binary, so the compiler's own
   source cannot use a feature the pinned binary lacks. The slices are therefore
   listed flat in `compiler.pas` rather than nested under one file — which also
   matches how every other frontend is spelled there. Nesting becomes available
   only after a compiler carrying the fix is pinned; it is not needed.

### One real defect, caught by the gate

Rewriting the residue's tail into a single map deleted `procedure ParseExpr;
forward;`, which happened to sit *between* two pointer comments. **pxx pre-scans
declarations and did not care — the fixedpoint passed.** The FPC seed canary
failed, which is exactly the "gap only the fpc-bootstrap job sees" that file's
own comment warns about. Restored with a note saying so.

### Not done — the remaining half

**The lexer is not carved out.** Pascal still shares `lexer.inc` with A (and the
Pascal-facing paths of `defs.inc`/`symtab.inc`), so the A/P no-concurrent-edit
rule still binds — over `lexer.inc`, not over one 37k-line file both lanes had
to queue behind. `pyparser.inc` (45k lines) is the same monolith shape and is
untouched. Filed as [[refactor-p-carve-out-paslexer-so-p-owns-its-lexer-too]].

Live docs updated to match: `CLAUDE.md` (Track P, the A/P slot, the shared-file
lists), `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`,
`session-roster.md`, `parallel-tracks.md`, `ir-as-substrate.md`,
`optimization-architecture.md` and five others; ~55 stale in-code pointers
re-aimed at the slice that now holds the code. Dated handover notes and
`devdocs/progress/**` were left alone — they are records of what a past session
saw, not instructions.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) after **each** of the
fourteen slices, plus `tools/gate.sh quick` GREEN — including the FPC seed
canary, which is the one that matters for a change that moves declarations
across include boundaries.

## Log
- 2026-08-20 — resolved, commit bbae00c78.
