---
prio: 60  # auto
---

# Esoteric/legacy frontend probes — umbrella (new category: "esoteric")

- **Type:** feature — umbrella, new category **esoteric-frontend-probe**
- **Status:** backlog — category definition + candidate list, no code yet
- **Owner:** —
- **Opened:** 2026-07-05 (user decision — Sunday-afternoon brainstorm, made concrete)
- **Priority:** unranked — opportunistic, pick up when convenient

## Core vs opportunistic (2026-07-05, user narrowing)

The **valid, first-class test surface** going forward is: **Pascal, C, BASIC,
and the Python dialect (Nil-Python)**. These are the frontends actually worth
investing real effort in (Pascal = the product; C/BASIC/Nil-Python = proven,
already-real cross-language-import demonstrations — see
[[feature-pxx-basic]]). Rust stays parked at its current landed state (3/12,
per the earlier "no need beyond proving the concept" decision) — not core,
not being advanced further either.

**Everything else in this umbrella (Ada, Algol, Fortran, COBOL, Zig, Erlang,
LOLCODE, Whitespace) is explicitly opportunistic, not core.** Pick one up only
when it sounds fun/cheap in a given session; none of them compete for
priority against real work. This also relaxes the "must be a compiled
skeleton" expectation for anything in this outer ring — COBOL, for instance,
is now fine as an interpreter instead of a frontend (see
[[feature-esoteric-cobol]]'s "Scope relaxed further" note) purely as a
pragmatic scope call, not because it needs that treatment the way Lisp does.

## The category, stated plainly

A **skeleton-only** frontend (lexer + parser for a trivial subset, lowering
straight onto the *existing* shared IR — no new IR primitives, no new backend
work) for a language chosen for how *differently shaped* it is from anything
PXX already parses, done **specifically to shake bugs out of shared internals**
that Pascal/C/Nil-Python/Rust never think to exercise.

**Restated even more precisely (2026-07-05, user correction):** the real goal
is not "compile language X" at all — it's **proving AST/IR correctness**.
"Oh, and it compiles Fortran" is the funny side effect people notice, not the
actual point. The point is that feeding a structurally-different program
through the shared lexer→AST→IR→backend pipeline is a differential test of
that pipeline's correctness — the specific source language is just a vehicle
for generating a test case shaped unlike anything the existing test suite
thinks to write. Keep this framing in mind when picking candidates: the
question is "what shape of program would exercise the AST/IR in a way nothing
else does," not "which language would be a cool demo" (that's
[[feature-pxx-basic]]'s job, a different bucket entirely — see below).

**The goal is explicitly NOT "make the language work."** Inverted success
criteria, stated up front so nobody chases scope later:

- **Finds a bug in shared IR/codegen/ABI** → the probe earned its keep. File
  the bug as its own ticket immediately (Track A), same as
  `bug-selfhost-multifn-ifelse-miscompile` came out of the Rust skeleton
  landing. This is the *expected*, valuable outcome.
- **Compiles and runs correctly, first try, no bugs found** → also fine, not a
  failure. It means the shared internals are more robust than assumed for that
  shape of program. Cheap confirmation, still worth having done it.
- **Either way, stop at skeleton depth.** Do not chase "compiles a real
  program in this language." That escalation is explicitly what happened with
  Rust (12 sub-tickets, "multi-week project") and what was rejected for Zig
  (comptime engine) and de-prioritized for Erlang (scheduler) — those stay
  parked *as full-language efforts*. A skeleton-only pass at any of them is
  back in scope under this category, precisely because the scope is capped.

## Precedent (why this isn't a new idea, just a named one)

- The C frontend's whole multi-session bring-up repeatedly surfaced shared
  bugs unrelated to C itself.
- Landing the Rust skeleton (3/12 sub-tickets, [[feature-rust-frontend]])
  surfaced `bug-selfhost-multifn-ifelse-miscompile` — a pre-existing shared
  bug, found *because* Rust's syntax shape hit a code path Pascal never does.
- `examples/lisp/lispdemo.pas` similarly proved the RTL robust enough to host
  a real interpreter — different axis (RTL capability, not frontend), same
  spirit: an unusual workload finds things a normal one doesn't.

## Candidates (add more as they come up — this list is not exhaustive)

| Candidate | Why it's a good/different probe shape | Notes |
| --- | --- | --- |
| **Zig** (skeleton only) | C-like type theory, own lexer/parser needed (not a C superset — confirmed this session). Full comptime engine stays out of scope. | See [[feature-zig-frontend]] (parked for full-language effort; skeleton subset still fair game here). |
| **Erlang** (skeleton only) | Pattern-matching-as-dispatch, immutability — different control-flow shape than anything else attempted. Full scheduler/actor-model stays out of scope. | See [[feature-erlang-frontend-scoping]] (same: full effort deprioritized, skeleton subset fair game). |
| **LOLCODE** | Dynamically typed, BASIC-shaped, informal/loose grammar (`HAI`/`VISIBLE`/`GIMMEH`). Likely the single cheapest candidate on this list. | New, see [[feature-esoteric-lolcode]]. |
| **Whitespace** | Syntax is *only* whitespace characters — the opposite extreme from every other frontend's token-based lexer. Genuinely different lexer shape (no visible tokens at all). | New, see [[feature-esoteric-whitespace]]. |
| **Ada** ⭐ **chosen next pick** | User's own hunch: "should be trivial" — Ada is Pascal's own language family (strong static typing, `begin`/`end`, similar declaration shape), plausible easy win and a good sanity check that the IR's Pascal-shaped assumptions generalize to a close cousin, not just Pascal itself. Ranked over the others (2026-07-05) because it tests IR generality (a kinship question), where COBOL/Fortran/LOLCODE/Whitespace mainly test grammar-shape diversity (already well covered by C/Rust/Nil-Python). | New, see [[feature-esoteric-ada]] for the full ranking rationale. |
| **Fortran** | Old, array-heavy, historically column-sensitive fixed-form source, GOTO-heavy control flow, quirky implicit-typing rules (pre-F90). Different enough era/shape to be worth a look. | New, see [[feature-esoteric-fortran]]. |
| **COBOL** | Verbose, English-like syntax (division-based structure: IDENTIFICATION/ENVIRONMENT/DATA/PROCEDURE DIVISION), fixed-decimal `PICTURE`-clause data types unlike anything else on this list. Genuinely different shape, good fuzz diversity. | New, see [[feature-esoteric-cobol]]. |
| **Algol (1958)** | Even stronger kinship test than Ada: Algol60 is Pascal's direct ancestor (parent→child, not siblings). If a trivial Algol subset doesn't lower cleanly, that's a sharper signal the IR is Pascal-specific than Ada would give. Trivial by the same logic as Ada/Fortran. | New, see [[feature-esoteric-algol]]. |
| ~~**Lisp**~~ | Correctly excluded, not just deprioritized: different paradigm entirely (homoiconic S-expressions, dynamic typing, cons-cell memory that can form real cycles — refcounting doesn't cleanly suffice the way it does for Erlang's acyclic-by-construction terms). Not a "trivial" probe by any honest reading. Already satisfied differently: `examples/lisp/lispdemo.pas` is a real Lisp *interpreter* written in Pascal (done, proves RTL capability) — user is explicitly lax about not needing a compiled Lisp *frontend* on top of that. No ticket filed for a Lisp frontend; the interpreter already covers the spirit of it. | See `devdocs/progress/done/feature-demo-lisp.md` for what exists today. |

## Explicit non-goals (the whole point of this category)

- Not a commitment to ship any of these as usable frontends.
- Not competing with Rust for "real second language" status — this category
  is bug-probing, Rust (parked at 3/12) is the one actual attempt at
  real-language usability.
- Not scheduled, not prioritized against each other — pick whichever sounds
  fun/cheap in a given session.

## Log
- 2026-07-05 — filed per user decision: reframe exotic/joke-tier frontend
  ideas (Zig, Erlang, LOLCODE, Whitespace, plus new candidates Ada/Fortran/
  COBOL) not as feature requests but as a deliberate, capped bug-finding
  technique. New ticket category "esoteric-frontend-probe" established.

## Status sweep (2026-07-07, Track Z session — two days, six probes closed)

| Candidate | Status | Outcome |
| --- | --- | --- |
| Ada | done (2026-07-05, earlier session) | clean pass; 2 frontend-local bugs |
| Zig | done (2026-07-06) | clean pass; `/`-must-be-tkDiv lesson (rparser has the same latent hazard) |
| LOLCODE | done (2026-07-06) | clean pass; paramless-recursion pitfall struck again |
| Whitespace | done (2026-07-06) | **found + filed [[bug-impl-prescan-late-include-var-section]]** (Track A); also proved a tokenless frontend works |
| Fortran | done (2026-07-06) | clean pass; documented the AN_ARG decimals-sentinel sharp edge (0 = zero decimals, -1 = none) |
| Algol | done (2026-07-07) | **kinship holds** — the IR lowers its own ancestor cleanly; RSeqAppend raw-head sharp edge documented |
| Erlang (skeleton) | done (2026-07-07) | pattern-dispatch shape handled cleanly; NumParams-vs-ParamCount field trap; scoping ticket unchanged in backlog |
| COBOL | open | relaxed to interpreter-scope (see ticket); the one remaining candidate, a bigger unit of work |

Aggregate verdict after seven shapes: the shared AST→IR→x86-64 pipeline has
taken every grammar family thrown at it (Pascal-kin, C-kin, dynamic-ish,
tokenless stack machine, implicit-typing, pattern-dispatch) without a single
shared CODEGEN bug. What the probes actually surface, consistently, is
(a) frontend-API sharp edges (ARG formatting sentinels, RSeqAppend head
contract, unset-field traps) and (b) one real prescan bug. That is exactly
the differential-testing value the category was created for; the marginal
value of further grammar-shape diversity is now low. COBOL stays available
as opportunistic; nothing else queued.
