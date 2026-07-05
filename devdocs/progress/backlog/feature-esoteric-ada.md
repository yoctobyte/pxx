# Esoteric probe: Ada

- **Type:** feature — esoteric-frontend-probe
- **Status:** sub-ticket 1 (skeleton) DONE 2026-07-05 — see closing log below; sub-tickets 2-4 still backlog
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Strongly statically typed, `begin`/`end`-block imperative language, same
Pascal/Algol family lineage as PXX's own primary language. Packages,
strong range-checked types, tasking (concurrency) in the full language.

## Why it's a good probe

User's own hunch: "should be trivial," because Ada is close kin to Pascal
(declaration shape, block structure, strong typing) rather than a foreign
paradigm. Good sanity check that the IR's Pascal-shaped assumptions actually
generalize to a close cousin rather than being accidentally Pascal-specific —
if this ISN'T trivial, that itself is an interesting finding (means the IR is
more Pascal-coupled than assumed).

## What already exists to reuse (confirmed by reading the tree, not assumed)

- `AN_TRY_EXCEPT`/`AN_TRY_FINALLY` (defs.inc ~140-142) + the class-descent
  exception-match machinery (`IR_EXC_MATCH`/`IR_EXC_MATCH_HIT`) — Ada
  exceptions (`raise`/`exception when ... =>`) map onto the same shape
  Pascal's `try`/`except` already lowers to. No new primitive needed for a
  basic subset.
- `GenericFuncs`/`GenericMethods` (defs.inc ~806-807), the same
  monomorphization engine Rust's generics reuse — Ada generics (`generic`
  packages/subprograms with `is new` instantiation) are a plausible fit for
  the same specialization mechanism, though Ada's generic *formal parameter*
  shape (types, subprogram-as-parameter, discrete-range parameters) is richer
  than Pascal's — needs its own check pass, not a free ride.
- Records / variant records — Ada records (including discriminated/variant
  records) map onto `tyRecord` the same way C structs and Rust structs
  already do.
- Units/packages — Ada's `package`/`package body` split (spec vs.
  implementation) is a closer match to Pascal's own unit
  interface/implementation split than anything else on the esoteric-probe
  list; likely the single most "free" piece of Ada relative to Pascal.
- Named parameter passing (`Foo (X => 1, Y => 2)`) and default parameter
  values — PXX already supports method/constructor default parameters
  (pinned v175, per recent history) — a plausible reuse point for Ada's own
  named/default-parameter call conventions, though named-parameter-by-name
  at the call site (not just defaults) is a new parser-side concern.

## Explicit non-goals (v1 scope cut, following the Rust/Zig/C precedent)

- **No tasking (concurrency).** Ada's `task`/`protected` types are their own
  concurrency model; if ever pursued, desugar onto the existing coroutine
  runtime like Rust's `async` plan — not a v1 target.
- **No full Ada generics.** Only concrete, already-instantiated generic
  usage in v1 (mirrors Rust's "no borrow-checker proof" style cut) — the
  richer formal-parameter shapes (generic formal subprograms, generic formal
  packages) are deferred.
- **No SPARK / formal-verification subset.** That's a proof system layered
  on Ada, out of scope entirely.
- **No `Ada.Text_IO`/standard-library breadth up front.** A thin
  `Put_Line`/`Get_Line`-shaped shim only, grown on demand like every other
  frontend's RTL did.
- **Compiling arbitrary existing Ada codebases is out of scope** — same rule
  as every other frontend's non-goal list.

## Scope (skeleton — capped per the umbrella's category rule)

Per [[feature-esoteric-frontend-probes]], this stays skeleton-only unless
explicitly re-scoped later (the way [[feature-pxx-basic]] was pulled out of
the probe bucket into a real target — Ada could get the same promotion if the
skeleton lands well and there's appetite, but starts capped):

1. **ada-frontend-skeleton** — `alexer.inc`/`aparser.inc` (new files, same
   shape as `clexer.inc`/`cparser.inc`/`rlexer.inc`), entry point (`.adb`/
   `.ads` dispatch), minimal subset: `procedure`/`function`, basic scalar
   types (`Integer`, `Boolean`, `String`), `if`/`loop`/`exit`, `Put_Line`.
   Gates everything else.
2. **ada-packages-as-units** — `package`/`package body` mapped onto Pascal's
   unit interface/implementation split. Likely the cheapest sub-ticket given
   how close the two models already are.
3. **ada-records-and-exceptions** — records (incl. simple variant records)
   onto `tyRecord`; `exception`/`raise`/`when ... =>` onto the existing
   `AN_TRY_EXCEPT` machinery.
4. **ada-generics-concrete-only** — `generic` + `is new` instantiation for
   the concrete-usage-only cut described above, via `GenericFuncs`.

## Acceptance

For the skeleton (#1) alone: either (a) a shared IR/codegen/ABI bug is found
and filed as its own Track A ticket, or (b) a trivial "hello world"-shaped
program compiles and runs clean — both close the skeleton probe successfully,
per the umbrella's inverted-success-criteria rule. Sub-tickets 2-4 are
optional follow-on depth, not required to call the probe "done."

## Why this one, ranked over the other candidates (2026-07-05)

Asked directly which esoteric-probe candidate to pick first: Ada, over
COBOL/Fortran/LOLCODE/Whitespace, for a reason distinct from "which is
easiest." The others (COBOL, Fortran, LOLCODE, Whitespace) mainly test
"does this exotic grammar shape parse and lower cleanly" — a novelty
question the C/Rust/Nil-Python diversity already covers reasonably well.
Ada tests something none of them can: **is the IR actually general, or
quietly Pascal-specific in ways nobody's noticed?** Same block-structure/
strong-typing family as Pascal, so if a trivial Ada subset *doesn't* lower
cleanly onto existing IR, that's itself the interesting finding — evidence
the "shared IR" story is more Pascal-coupled than assumed, worth knowing
regardless of Ada itself. Kinship test, not a novelty test — higher signal
per unit of effort than the others on this list.

(COBOL stays the pick if the goal shifts to pure fun-demo value instead —
its DIVISION-structured, English-like syntax is the best callback to the
session's "platonic language / closest to human expression" tangent.)

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.
- 2026-07-05 — chosen as the next pick when asked directly which candidate
  to prioritize; reasoning above. Not started, still backlog — a choice of
  *order*, not a greenlight to build yet.
- 2026-07-05 — expanded to umbrella depth (matching the Rust/Zig ticket bar)
  at user request: confirmed reuse candidates by reading the tree
  (exception machinery, monomorphization, records, default-param support),
  explicit non-goals, and a 4-sub-ticket skeleton→packages→records/exceptions
  →generics breakdown. Still capped at skeleton-only per the umbrella's
  category rule unless explicitly re-scoped later, same as
  [[feature-pxx-basic]] was pulled out of the probe bucket when it earned
  that promotion.

## Sub-ticket 1 (skeleton) DONE — 2026-07-05

Built on branch `feature/ada-frontend-skeleton`, verified additive-only
before merge (see acceptance below). `compiler/alexer.inc` (lexer) +
`compiler/aparser.inc` (parser), wired via 3 minimal touches to
`compiler.pas`/`defs.inc` mirroring the exact pattern C/BASIC/Rust already
established (an `isAda` boolean, `.adb` extension detection, one dispatch
branch) — no new AST nodes, no new IR, no backend work, confirming the
umbrella's premise that Ada's Pascal-kinship makes it lower cleanly onto
existing machinery.

**What compiles and runs, verified with a real regression test**
(`test/test_ada_skeleton.adb`, wired into `Makefile`'s test-core target):
single top-level `procedure Name is <decls> begin <stmts> end Name;`
program shape; `Integer`/`Boolean`/`String` var declarations with optional
initializers; assignment; `if`/`elsif`/`else`/`end if`; `while ... loop ...
end loop`; bare `loop ... end loop` (desugars to `while True`); `for I in
lo..hi loop` (desugars to init+while+increment, same technique BASIC's
`FOR` already uses); `exit` / `exit when` (loop break — see bug below);
`Put_Line(expr)` (same `AN_WRITE`/`AN_WRITELN`/`AN_ARG` shape as BASIC's
`PRINT`); `--` line comments; double-quoted strings with `""`-escaped
quotes.

**Two real bugs found and fixed while building this — both mine, not
compiler bugs, but worth recording since they're exactly the kind of
mistake this project's own conventions exist to prevent:**

1. **Paramless recursive self-call without parens silently reads the
   Result variable instead of recursing.** Wrote `elseNode :=
   ParseAStatement;` (no parens) for the `elsif`-handling recursive call —
   per this project's documented paramless-function-name semantics (a bare
   paramless function name inside its own body means "the Result
   variable," not "call myself"), this silently did NOT recurse, returned
   whatever `Result` happened to hold, and looked like a hang/dispatch bug
   until isolated to a minimal 15-line plain-Pascal repro. Fixed: `elseNode
   := ParseAStatement();` (explicit parens) at both call sites. This is
   already documented in project memory (`frank2-paramless-name-semantics`)
   — I made the exact mistake that memory exists to prevent; recording here
   too since it's a sharp trap for any future frontend hand-writing
   recursive-descent parsers in this codebase.
2. **`exit`/`exit when` mapped onto `AN_EXIT` (procedure/function exit)
   instead of `AN_BREAK` (loop break).** `tkExit` is BASIC's token for
   `RETURN` (procedure exit) — reusing it for Ada's `exit` silently exited
   the whole enclosing procedure the first time a loop's exit condition
   fired, truncating all output after it (looked like a working program
   with a suspiciously short run, not a crash). Fixed: lex Ada's `exit` to
   `tkBreak` (the same token Rust's `break` uses) and build `AN_BREAK`
   nodes instead of `AN_EXIT`. Caught by testing actual program output
   against expected, not by inspection — this is exactly the "silent-wrong
   is worse than a compile error" pattern this project already tracks
   (parallels the BASIC GOTO/GOSUB bug found earlier this session).
3. **Also added a parser-hang guard in `ParseABlock`** (not a bug found,
   a defense added after almost hitting one): before the bare-`loop`
   support existed, a bare `loop` token wasn't recognized by any statement
   branch, `ParseAStatement` returned -1 without consuming a token, and
   `ParseABlock`'s loop spun forever. Fixed the missing case AND added a
   `TokPos`-didn't-advance guard that now `Error`s clearly instead of
   hanging, for any future unhandled construct.

**Verification:** `make -k test` full suite green (244 passing compiles;
the only failure is a pre-existing, unrelated missing external dependency —
`library_candidates/tiny-regex-c` — confirmed present on clean `master`
before this branch too). `tools/gui_suite.sh` and `apps/ide/test.sh` both
green (confirms the shared `compiler.pas` dispatch touch has zero effect on
GUI/Eliah). `make cross-bootstrap-i386` byte-identical (confirms zero
effect on cross-target self-host). `tools/fuzz.sh --minutes 1` clean (0
divergences) both before and after this branch's changes.

**Not done (sub-tickets 2-4, still backlog):** packages/units, records,
exceptions, generics. This closes only the skeleton acceptance bar from
this ticket's original scope section.
