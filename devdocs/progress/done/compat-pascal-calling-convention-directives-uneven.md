---
track: P
prio: 60
type: bug
summary: "`stdcall`/`safecall`/`pascal`/`mwpascal` are accepted on a class METHOD declaration but are a parse ERROR on a plain routine, an `external`, or a procedural type — so FPC sources that spell a convention on a routine do not compile, and which spelling works depends on where it is written."
status: done
owner: opus5-frank1
---

# Calling-convention directives are accepted in some positions and rejected in others

- **Type:** bug (Pascal frontend — dialect surface) — **Track P**, tag compat
- **Found:** 2026-08-03 while documenting calling conventions for
  `docs/language/dialect.md` (Track D discovery → ticket, not an inline fix).

## Measured

Same compiler, same directive, four positions. Identical on HEAD and on the
pinned binary, so this is shipped behaviour, not a regression:

| directive | routine w/ body | `external` | procedural type | method decl |
| --- | --- | --- | --- | --- |
| `cdecl` | ok | ok | ok (**and meaningful**) | ok |
| `register` | ok | ok | **REJECT** | ok |
| `stdcall` | **REJECT** | **REJECT** | **REJECT** | ok |
| `safecall` | **REJECT** | **REJECT** | **REJECT** | ok |
| `pascal` | **REJECT** | **REJECT** | **REJECT** | ok |
| `mwpascal` | **REJECT** | **REJECT** | **REJECT** | ok |

```
pascal26:2: error: unexpected token
  near:  Integer   >>> stdcall
```

A REJECT is a parse error, not a warning.

## Why it matters

The project's design rule is that a calling convention is the **target's** — the
markers are decoration (user, 2026-08-03: *"we just treat any calling definition
as pure decoration … any calling convention is host specific by definition"*).
Decoration should be *accepted and ignored*, uniformly. Instead the accepted set
depends on where the word appears, which is the worst of both worlds: it carries
no meaning, and it still refuses to compile real FPC code.

`stdcall` in particular is all over Windows-facing FPC sources, and
`safecall` all over COM-facing ones. A port hits a parse error on a directive
that would have been ignored had it been written one line lower, inside a class.

## The asymmetry in the code

Two independent lists, which is why they disagree:

- the routine-directive skip loop in `ParseSubroutine` (`compiler/parser.inc`,
  the `while ((CurTok.Kind = tkIdent) and (... 'inline' ... 'register' ...
  'cdecl' ...))` loop) accepts only `inline`, `register` and `cdecl` among the
  conventions;
- the method-declaration path uses a separate predicate that accepts `cdecl`,
  `stdcall`, `safecall`, `register`, `pascal` and `mwpascal` (guarded on a
  following `;`, since none of these are reserved words).

The procedural-type path accepts `cdecl` only.

## Fix shape

Give all four positions ONE predicate — the method path's set is already the
right one, and its `;` guard is what makes accepting non-reserved words safe
(a field named `register` stays a field because `register: Integer;` has a `:`
next). Accept and ignore, uniformly.

**Do not** make any of them change the ABI. `cdecl` on a **procedural type** is
the sole exception that must keep its meaning: it marks the signature C-ABI so
an indirect call through a C function pointer marshals correctly (measured:
without it a `dlsym`'d `double dtwice(double)` called through the type returns
21.0 for an argument of 21.0; with it, 42.0). Whether the other spellings should
also mark a procedural type C-ABI is a smaller question — on the supported
targets they would all mean the same thing as `cdecl`.

## Sequencing — deliberately left at prio 35

User, 2026-08-03, on whether to raise it: *"nah don't bother we will get there
once we start working on windows target."*

That is the right pairing: `stdcall` and `safecall` are Windows/COM spellings,
so the sources that trip over this are the ones a Windows port brings in.
Picking it up alongside [[feature-port-windows-pe]] also answers the open
sub-question here — whether the non-`cdecl` spellings should *mark* a procedural
type C-ABI — with a real target where the answer might not be "same as cdecl".

So the 35 is a decision, not neglect. Do not re-rank it on the grounds that it
is a parse error; take it when Windows work starts.

## Gate

Each of `cdecl`, `stdcall`, `safecall`, `register`, `pascal` and `mwpascal`
compiles in all four positions; `cdecl` on a procedural type still yields 42.0
through the dlsym probe; self-host fixedpoint byte-identical.

## Docs

`docs/language/dialect.md` documents the current uneven table as-is, plus the
procedural-type exception. When this lands, that table collapses to "accepted
everywhere, meaningful only on a procedural type" and the doc needs the edit.

## Outcome — 2026-08-27

Taken now rather than with the Windows port, because the two halves of this
ticket separated cleanly and only one of them was waiting on a target.

### Three of the four positions were already fixed

Re-measured all 24 cells before touching anything. The table in the ticket is
stale: `IsCallConvDirectiveTok` (`pasparser_call.inc`) had already collapsed the
routine, `external` and method lists into one — its own comment says *"ONE list,
five call sites, deliberately: each of those loops grew its own spelling of the
set and they drifted apart"*. So the whole `stdcall`/`safecall`/`pascal`/
`mwpascal` row read `accepted` in three of four columns.

What was left was the fourth: the **procedural type**, whose `EatProcTypeCdecl`
still spelled `cdecl` inline and took nothing else. Six spellings × one position.

### What landed

`EatProcTypeCdecl` → **`EatProcTypeCallConv`**, and both it and
`IsCallConvDirectiveTok` now ask one new `IsCallConvName(s)` for the spellings.

The dedup is deliberately of the LIST and not of the guard. The two sites look
at different tokens — a directive list reads `CurTok` and needs the
not-a-reserved-word check (`register: Integer;` is a field), while a procedural
type peeks one token past its own `;`. Sharing the guard as well is exactly what
made the procedural-type site keep its own hard-coded copy in the first place,
so the fix that would have caused the drift again is the one not taken.

**Only `cdecl` still marks anything.** `ProcCdecl[mpi] := True` is now guarded on
the spelling rather than being the whole point of the procedure. The ticket's
open sub-question — *"whether the other spellings should also mark a procedural
type C-ABI"* — is answered `no` for `register` on its own merits (it is FPC's
convention, not C's; marking it would be marking it wrong), and left open for
`stdcall`/`safecall`, which is the half a real Windows target answers.

### Measured

All 24 cells, six spellings × four positions:

| directive | routine w/ body | `external` | procedural type | method decl |
| --- | --- | --- | --- | --- |
| `cdecl` | ok | ok | ok (**and meaningful**) | ok |
| `register` | ok | ok | ok *(was REJECT)* | ok |
| `stdcall` | ok | ok | ok *(was REJECT)* | ok |
| `safecall` | ok | ok | ok *(was REJECT)* | ok |
| `pascal` | ok | ok | ok *(was REJECT)* | ok |
| `mwpascal` | ok | ok | ok *(was REJECT)* | ok |

`test/test_calling_convention_directives_everywhere.pas` (+ `.expected`, wired
into `test-core`) covers every cell in one program, and carries the **negative**
half too: a `Double` and an `Integer` through a `register`, a `stdcall` and a
plain procedural type all reach a pxx routine by pxx's internal convention and
come back `6.0`. If a future edit marked those C-ABI, that row is what fails.

Output is byte-identical to `fpc -O1 -Mobjfpc` 3.2.2, which took two adjustments
to the test and both are findings:

- FPC **type-checks the pairing** — it refuses `@TwiceRegister` into a `stdcall`
  procedural variable. pxx does not, and cannot: a convention it does not model
  cannot make two signatures incompatible. Accepting more than FPC is not a
  defect (CLAUDE.md), and the test now declares each routine with the convention
  of the variable it goes into so both compilers take it.
- FPC **models `safecall`**: its result rewrite makes `XSafecall` answer `0`
  where every other spelling answers the pid. That row is declared, and
  deliberately not asserted on.

`test/test_cdecl_indirect.pas` (the dlsym `sqrt`/`pow`/`ldexp` probe) still
answers `4.0 / 1024.0 / 12.0`, which is the gate this ticket asked for.

### Docs

`docs/language/dialect.md` — the uneven table collapses to "accepted
everywhere, meaningful only as `cdecl` on a procedural type", with the
`register`-is-not-C note and FPC's pairing check written down; the "Not
accepted" section is now `varargs` alone.
`docs/language/fpc-compatibility.md` — the porting note no longer tells the
reader to strip `stdcall`.

### Gate

`make compiler/pascal26` byte-identical (8f7cb2b0abf9) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
