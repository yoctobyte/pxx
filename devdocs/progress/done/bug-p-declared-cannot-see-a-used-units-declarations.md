---
track: P
prio: 50
type: bug
blocked-by: []
status: done
summary: "FIXED 2026-09-09, both halves. `{$if declared(X)}` answered False for a name declared in a used unit -- silently taking the `{$else}` arm for a type the same program then constructs -- because `PasCondNameDeclared` scans the token stream and `LexAppend` puts a unit's tokens there at PARSE time, after every conditional in the main file is decided. NOW: `PasCondNameDeclaredInUses` asks `ResolveUsesUnitSource` for the source, LEXES it into a scratch region and scans the TOKENS. IT LEXES RATHER THAN SCANNING TEXT because 151 of 400 real FPC interfaces (38%) carry an `{$I}` include -- a text scan answers False for a name in an include it never opened, this defect one level down, and `lib/rtl` is 0/111 on includes so a fixture built from our own RTL cannot sample it. THE THIRD ANSWER IS A WARNING, NOT A REFUSAL: refusing would regress every defensive declared() in a program with any `uses`, the Synapse shape the operator was written for. THE FIX REINTRODUCED A CLOSED BUG AND ITS OWN CONTROL CAUGHT IT -- lexing a unit RUNS ITS DIRECTIVES, so without the new save/restore a used unit's `$DEFINE` escaped into the main program ([[bug-p-a-units-define-leaks-into-the-units-it-uses]] exactly); that pair is a second enumeration of the directive set, so `tools/probe_state_lists.py` (in gate.sh, positive control asserted) checks it against `PasSnapshotDirectiveBaseline`. ARITY DONE TOO, and it turned out to be the GATE on `tgeneric93.pp` rather than its second half -- that file died at its first conditional, `declared(NotDeclared<>)`, before the unit question was asked. `<>`=1, `<,>`=2, `<,,>`=3, a bare name asks arity 0 as a real question (grepped: no real code asks a bare declared() of a generic, so the behaviour change has an empty population), only EMPTY slots are legal, and the scan no longer returns on a name match because one name can be declared at several arities. The objfpc trap was real: `generic` is a plain tkIdent that ATE the declaration slot, so every objfpc generic answered False while the row that would expose it agrees for the wrong reason -- fixture asserts two digits and a control binary gives `objfpc 00`. tgeneric93.pp now passes (harness: 1 pass 0 fail 0 skip), its pxx.skip entry removed; in-repo fixture byte-identical to fpc across all seven rows because library_candidates/ is gitignored. STILL OPEN: transitive `uses` only, which tgeneric93 does not need."
owner: frankZ
---

# `{$if declared(X)}` cannot see a used unit's declarations, and answers False rather than refusing

Measured 2026-09-06 at compiler `d697a8a680fd`. `uu1` declares
`TPlainUnit = class`; the program `uses uu1`, and in the same program:

    v := TPlainUnit.Create;              { works — the type is fully usable }
    {$if declared(TPlainUnit)} A = 1 {$else} A = 0 {$endif}

    pxx:  the type IS usable: TRUE   declared() says=0
    fpc:  the type IS usable: TRUE   declared() says=1

A local declaration in the same file answers True correctly, so the operator
works; what it cannot see is the other side of a `uses`.

## Cause, and why it is not a small fix

`PasCondNameDeclared` (paslexer.inc) answers by scanning
`Tokens[0..TokCount-1]`, and its own header states the model honestly: only
declarations *already emitted* are knowable. A used unit's tokens are appended
to that same stream by `LexAppend` — but from `pasparser_proc.inc:5745`, at
PARSE time. The order is: LexAll(main) → conditionals resolved → parse → `uses`
→ LexAppend(unit). Every conditional in the main file is decided before a single
unit token exists.

Closing it means resolving and lexing a used unit *during* the main LexAll —
unit search paths, per-unit directive state, and recursion, in shared lexer
territory. That is why this is filed rather than fixed.

## Why it ranks above a missing diagnostic

Feature detection across a unit boundary is what `declared()` is FOR. The
failure is silent and takes the `{$else}` arm, and the `sizeof` arm eleven lines
below it in the same file already says what that costs: *"a conditional that
takes the wrong branch does not produce a wrong value -- it produces a different
program."* That arm refuses a name it cannot size for exactly this reason.
`declared` answers False instead, which is indistinguishable from a correct
negative — and a correct negative is the common case, so nothing looks wrong.

Note the asymmetry deliberately: refusing is NOT obviously the right repair here,
because False is the correct answer for the case the header was written for
(Synapse's `Posix.StrOpts.*` under a profile with no such unit). Whoever fixes
this has to separate "not declared" from "declared somewhere I cannot see yet",
and today the scan cannot tell those apart.

## The generic-arity half, measured while here

`tgeneric93.pp` needs this AND the arity spelling. Both halves measured:

| form | pxx | fpc |
| --- | --- | --- |
| `declared(TDel)` where only `TDel<T>` exists, delphi mode | True | **False** |
| `declared(TFpc)` where only `generic TFpc<T,S>` exists, objfpc | False | False |

The objfpc row agrees for the wrong reason: `generic` is a plain `tkIdent`
here (there is no `tkGeneric`), so it consumes the scanner's `expectName` slot
and `TFpc` is never examined at all. Any arity work must handle that first or it
will answer False for every objfpc generic while looking correct on this row.

The arity spelling itself is otherwise cheap: `<>` = 1 param, `<,>` = 2,
`<,,>` = 3; peek from the matched name token for `tkLt`, count commas at depth 1
to the matching `tkGt`, and keep scanning on an arity mismatch rather than
returning on the first name hit — `TTestDelphi<T>` and `TTestDelphi<T,S,R>` are
two declarations of one name, and pxx already supports that overloading (all
four of `TA<T>` / `TA<T,S,R>` / `TB` / `TB<T,S>` construct correctly today).
None of it helps tgeneric93 until the unit half lands: every name that row
probes lives in `ugeneric93a` / `ugeneric93b`.

Changing the bare form to require arity 0 is a behaviour change for any existing
`declared(SomeGeneric)`; grep before landing it.

## 2026-09-09 — still reproduces, unchanged

Re-measured at commit `69a5f3c6f`, binary `5d5dcb45d328` (stamp removed and the
build forced to `converged after 1 round(s)`, because `make` printed `verified`
with nine build inputs moved).

```
the type IS usable: TRUE
declared() says=0
```

Same shape as filed, same asymmetry: the type is fully usable in the same
program in which `declared()` answers False. Nothing above has gone stale — the
cause section still describes the code, and the fix is still the one it says it
is (resolving and lexing a used unit DURING the main `LexAll`, in shared lexer
territory). Confirmed rather than attempted, so the next reader does not have to
re-establish that the repro is live.

Also worth carrying to whoever takes it: the note about separating "not
declared" from "declared somewhere I cannot see yet" is the whole difficulty,
and it is the same silent-negative shape as three of its neighbours in this
group — `--strict-visibility` accepting an unchecked record, and a `uses`
failure that cannot say a manifest went unread. Both of those were closed by
making the negative DISTINGUISHABLE rather than by making the lookup wider. That
is a hint about the shape of the answer here, not a design for it: `declared()`
returning False is correct for the case the operator was written for (a profile
with no such unit), so the repair has to add a THIRD answer, not flip the second.


## 2026-09-09 (frankZ) — the scope, measured before designing anything

Three measurements. Two of them close off the cheap version of this fix, and the
third says what the fix has to be.

**1. Refusing cannot be the third answer.** The tempting spend for "declared
somewhere I cannot see yet" is to REFUSE when the token stream holds a `uses`
whose units are not lexed. That is a regression for every defensive `declared()`
sitting in a program with any `uses` clause at all — which is Synapse's own
shape, and Synapse is the case the operator's header was written for. False is
the correct answer there. So the third answer can only be a **WARNING attached
to the False**, naming the units that were named but not read at
conditional-evaluation time. That is the same "make the negative
distinguishable" move that closed this ticket's three neighbours, and it is the
only spend that does not break the case the feature exists for.

**2. A Pascal-only resolver in the lexer is a NEW wrong answer, not a narrower
one.** The chain in `pasparser_proc.inc` runs 4928-5589 — roughly 660 lines, ~18
stages, `isPath` → `CurUnitDir` → `SourceFileDir` → `PasUnitDirs` →
`cdir`/`bdir`/`rtldir`/`lcldir` → the CWD-relative last resort — and the C
stages are **ordering-significant, not appended**. Measured at
`pasparser_proc.inc:5190`: a `.c` or `.h` next to the source sets `UnitContent`
and thereby BLOCKS the `-Fu` Pascal stage at 5236. So a Pascal-only copy answers
True about a `.pas` in a search root that the real compile never reads, whenever
a `foo.c` sits beside the program. That configuration is reachable and it is the
subject of a closed ticket
([[bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import]]),
which deliberately did NOT extend its reordering to `SourceFileDir` because a
`.c` beside the program is an explicit local choice. **The resolver has to be
the same code, not the same idea.**

**3. And the resolver alone is NECESSARY BUT NOT SUFFICIENT, which the ticket
did not say.** A raw token scan of a unit's source text answers about the text,
not about the declarations. Measured over 400 real FPC unit sources
(`/usr/share/fpcsrc/3.2.2`): **151 of 400 interfaces (38%) contain an `{$I}`
include and 94 (24%) contain a conditional.** For `lib/rtl` the numbers are
mild — 0 of 111 interfaces include, 11 carry a conditional — so **a fixture
built from our own RTL will not sample the population this operator serves.**
The include direction is the dangerous one: the name lives in an `.inc` the scan
never opens, and the scan answers False. That is this ticket's own silent
negative, reproduced one level down and invisible to any test written against
`lib/rtl`.

## What that makes the fix

Not a scan of unit text. **Lex the unit with the real lexer and scan the tokens.**
`LexAppend` (`lexer.inc:857`) already saves and restores `Source`, `SrcPos`,
`SrcLine`, `LexMarkDbgLines` and `Lexing`, and its own comment states it "runs
re-entrantly (a unit's own `uses` loads another unit mid-lex)" — so appending a
unit into a scratch region at the end of the stream during `LexAll`, scanning it,
and truncating `TokCount` back is using the machinery as designed rather than
working around it. Includes and the unit's own conditionals are then handled by
the thing that handles them everywhere else.

Which leaves exactly one blocker, and it is measurement 2: the search chain is
unreachable from the lexer because it is 660 lines in the middle of a parser
procedure. **Step one is a faithful extraction of 4928-5589 into one resolver
with one owner** — every stage, C and NilPy included, in the same order, so the
answer cannot differ from the compile's. That extraction is worth landing on its
own and is a prerequisite for any correct version of this fix.

Rejected alternative, recorded so it is not re-derived: DEFER the unresolvable
conditional to parse time by keeping both arms' tokens behind a marker. It
avoids the resolver entirely, and it fails because the two arms of a
`{$if declared(X)}` routinely declare the SAME NAME differently — so the parser,
not the lexer, would have to honour a skip marker at every declaration site.
That is more invasive than the extraction and lands the cost in a worse place.


## Fixed — 2026-09-09 (frankZ)

`declared()` now answers across a `uses`. The ticket's own repro prints
`declared() says=1` where it printed `0`, and
`test/test_declared_sees_a_used_units_declarations.pas` is byte-identical to
fpc 3.2.2.

**It LEXES the used unit rather than scanning its text**, which is measurement
(3) above turned into a design: `PasCondNameDeclaredInUses` asks
`ResolveUsesUnitSource` for the source, `LexAppend`s it into a scratch region at
the end of the token stream, runs the declaration scan over that range, and
truncates `TokCount` back. Includes and the unit's own conditionals are then
handled by the thing that handles them everywhere else. The scan itself was
split into `PasCondNameDeclaredIn(qname, lo, hi)` so the same walk can be
pointed at a range that is not `[0, TokCount)`.

The resolver is reached the way `paslexer.inc` already reaches the type table:
a forward in `compiler.pas`, beside `PasCondSizeOfTypeName`, whose own comment
says it *"forwards a QUESTION and carries no answer"* to avoid a second source
of truth. Same reason, same shape.

### The third answer is a WARNING, and the sizeof arm is why that needed saying

The `sizeof` arm eleven lines below refuses a name it cannot size, and that is
right there — a sizeof it cannot answer is always an error or unanswerable.
`declared` cannot copy it: False is what this operator EXISTS to return. So a
unit the probe could not read leaves the answer False and emits a warning naming
how many units were unreadable. Measured firing on a `uses` of a C unit, and NOT
firing when every named unit resolves.

### What it cost, and the control that says so

**Lexing a unit runs its directives.** Measured with the probe wired and no
save/restore: a `$DEFINE` in the used unit made the MAIN program's `$ifdef` take
the true arm where fpc takes the false one — i.e. this change reintroduced
[[bug-p-a-units-define-leaks-into-the-units-it-uses]], which
`PasResetDefinesToBaseline` exists to prevent. `PasProbeSaveLexState` /
`PasProbeRestoreLexState` wrap the probe; each probed unit is lexed FROM THE
COMMAND-LINE BASELINE, which is FPC's scoping rule and what the parser's own
unit load already does.

That created a SECOND enumeration of the same directive set, which is the defect
shape this repo has paid for repeatedly — so it is checked rather than trusted:
`tools/probe_state_lists.py`, wired into `gate.sh`, asserts the probe's save list
covers every global `PasSnapshotDirectiveBaseline` snapshots, that save and
restore are symmetric, and that the define arrays match. Its positive control is
asserted: delete one saved directive and it fails naming it.

**The fixture's four rows are read together and no single one discriminates**,
because each value is 0 or 1: `1/1/0/0` is correct, always-True gives `1/1/1/1`,
always-False `0/0/0/0`, and a probe with no state discipline gives `1/1/1/0`.
That last was measured on a control binary built for the purpose, not inferred.

**Cost:** ~40ms per FAILING `declared()` per used unit (12 failing calls over 4
RTL units: 1.6s against a 1.1s baseline). Only failing calls pay it — a hit in
the main file's own stream never reaches the probe. Not cached; if a corpus run
gets slow with many `declared()` guards over many units, this is the place.

## Still open — transitive `uses`, and that is all

- **TRANSITIVE `uses`.** Only units named in the file are probed, not units they
  name. FPC sees the transitive interface. The residual error is False-when-True,
  i.e. this same defect narrowed, and a probed unit's own conditionals do not
  probe (the depth guard) because `a uses b` and `b uses a` is legal and would
  not terminate. `tgeneric93.pp` does not need it — both its units are named
  directly — so nothing measured today is blocked on this.

## The arity half — also fixed, 2026-09-09

**I was about to rank this as a follow-up and the measurement said otherwise.**
The plan was that the unit half might be enough for `tgeneric93.pp`, since every
name it probes lives in `ugeneric93a` / `ugeneric93b` and both are directly
used. It got nowhere: that file's FIRST conditional, line 9, is
`{$if declared(NotDeclared<>)}`, and we answered `conditional directive:
declared requires (NAME)` at line 0 — dead in the preprocessor before the unit
question was ever asked. The arity spelling was not the second half of that row,
it was the gate on it.

`tgeneric93.pp` prints **OK** (all 11 rows), fpc prints OK, and
`run_pascal_conformance.sh --only 'tgeneric93*'` reports `1 pass, 0 fail, 0
skip`. Its `pxx.skip` entry is removed.

`ReadPasCondGenericArity` reads the `<>` / `<,>` / `<,,>` suffix as a count of
commas, and **only empty slots are legal** — `declared(TFoo<Integer>)` is
refused by name rather than counted as one parameter, because the operator asks
whether a TEMPLATE of that arity is declared, not whether an instantiation
exists. A permissive scan would have answered that silently.

**A bare name asks arity 0, and that is a real question rather than a
wildcard** — which is the behaviour change the earlier section said to grep for
before landing. Grepped: every `{$if declared(` in the tree and in the vendored
corpora is `tgeneric93.pp` (11, eight of them with the arity spelling) plus this
ticket's own fixture. **No real code asks a bare `declared(SomeGeneric)`**, and
tgeneric93 expects FPC's semantics, so the population that could regress is
empty.

The scan does **not** return on a name match any more. One name can be declared
at several arities in one unit — `ugeneric93a` has `TTestDelphi<T>` beside
`TTestDelphi<T,S,R>`, and `TTest2Delphi` beside `TTest2Delphi<T,S>` — so a walk
that stopped at the first name would answer about whichever came first and be
right by accident about half the time.

**And the objfpc trap the earlier section warned about was real.** `generic
TFoo<T, S> = class` has no `tkGeneric`, so `generic` arrived as a plain
identifier and CONSUMED the declaration slot; the type name was never examined
and every objfpc generic answered False. The row that would have hidden it is
`declared(TTestFPC)`, which is False under a working scan AND under a scan that
never looked — so the fixture asserts `objfpc 01`, two digits, and the second is
the only one that discriminates. Measured on a control binary with the slot fix
removed: `objfpc 00`, with `gen 0101` unchanged, so the control isolates exactly
that arm. The skip is guarded only where someone has fetched the suite —
`library_candidates/` is gitignored — which is why the arity and objfpc rows are
also in `test/test_declared_sees_a_used_units_declarations.pas`, byte-identical
to fpc across all seven rows.

Noticed while writing the fixture and NOT chased: fpc refuses a `{ }` comment
containing `{$if declared(X)}` in Delphi mode (`illegal character`) because it
closes at the first `}`, while pxx compiles it. Us accepting what FPC rejects is
not a defect by the rules, so it is recorded here rather than filed — but if it
means `NestedComments` is on under `{$mode delphi}` where fpc has it off, that
direction is worth someone's measurement.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 004793f42.
