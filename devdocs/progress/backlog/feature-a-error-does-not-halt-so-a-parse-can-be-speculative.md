---
track: A
prio: 45
type: feature
summary: "`Error()` calls `Halt` directly, so nothing in the compiler can trial-parse and back out. That blocks NilPy's type inference (which needs to read an as-yet-unseen name speculatively), and it is also why the compiler stops at the FIRST error. Make the error path recoverable; several unrelated wants fall out of the same change."
---

# `Error()` halts, so no parse can be speculative

- **Type:** feature (compiler core) — **Track A**.
  Split out 2026-08-14 by the user while re-pricing
  [[decide-reprice-nilpy-ast-typing-module-scope]]:

> *"It makes no sense to optimize a halt()."*

## The problem in one line

`Error()` calls `Halt` directly. So there is no way to attempt a parse, discover
it does not work, and carry on — the attempt kills the process.

## What that blocks, that we already know about

1. **NilPy module-scope type inference.**
   [[feature-n-nilpy-ast-typing-module-scope]] wants a pre-pass that trial-parses
   the RHS of a binding whose name has not been seen yet. It cannot, so it
   carries a hand-maintained "safe shape" list instead, and anything not on the
   list widens to `tyVariant`. Its own note calls the recoverable pre-pass *"the
   real close"*, after which the safe-shape list **disappears** rather than
   being extended. That ticket is now prio 8 because it cannot be worked until
   this lands.
2. **Multiple errors per compile.** Halting at the first one is the same
   constraint wearing a different hat: a user fixing ten mistakes gets ten
   compile cycles.
3. **Any future speculative parse** — overload resolution that wants to try a
   shape, a frontend probing whether a construct is legal before committing.

The pattern to notice: three unrelated wants, one plumbing cause. That is
usually the sign the plumbing is the real ticket
(`devdocs/dev/root-cause-over-microfix.md`).

## Shape, not a prescription

The obvious approach is an error *sink* — collect rather than halt, with an
explicit "abort now" for the cases that genuinely cannot continue (a corrupt
read, an internal invariant). Two things to work out rather than assume:

- **What state must be unwound** when a speculative parse fails. A trial parse
  that has already registered symbols, allocated types or emitted IR has to be
  rolled back or scoped, and that is the real work here — not the error call
  itself.
- **Which errors are genuinely fatal.** Turning everything recoverable risks a
  compiler that limps on producing cascading nonsense, which is worse than
  stopping. FPC's own behaviour is a reasonable reference point.

## Not urgent, but it unblocks more than it looks

Nothing is broken today. Filed at 45 because it is the shared cause behind at
least three separate wants, and because one of those (NilPy inference) is
otherwise permanently parked.

## Gate

A parse that fails inside a speculative attempt leaves the compiler able to
continue and produce a correct result for the non-speculative path; `make
compiler/pascal26` fixedpoint byte-identical; `tools/gate.sh quick` GREEN.
Plus the property that makes it worth doing: a file with two independent syntax
errors reports both.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged — and the cheap symptom still
reproduces.** A program with two undefined names reports only the first:

```
pascal26:3: error: undefined variable (undefined_one)
```

`undefined_two` is never mentioned, because `Error()` still halts. That is item
2 of the ticket, measured; items 1 and 3 follow from the same mechanism.

Not re-typed: halting at the first error is a quality-of-implementation
limit, not a wrong answer. Worth noting for ranking, though, that this ticket
is a **blocker with priority propagating down to it** — its item 1 is why
`feature-n-nilpy-ast-typing-module-scope` sits at prio 8 — so the N deferral
does not lower it; items 2 and 3 are A/P-facing on their own.

## Slice 1 landed 2026-08-24 (claude-A) — the error path can return, and item 2 is real for names

**What landed.** `Error` was one procedure that formatted a diagnostic and then
`Halt`ed. It is now three: `ErrorPrint` (the only place a diagnostic is worded,
so the `in:` line and the `near:` window cannot drift between callers), `Error`
= print + halt, and **`ErrorRecover`** = print, count into `ErrCount`, and
**return**. The Pascal frontend's four "this name does not resolve" sites take
the recovering path; the driver halts on `ErrCount > 0` immediately after
`ParseProgram`, before RTTI, fixups or any output.

The ticket's own measured symptom:

```
$ pascal26 e1.pas -o e1
pascal26:3: error: undefined variable (undefined_one)
pascal26:4: error: undefined variable (undefined_two)
$ echo $?   ->  1     $ ls e1   ->  no such file
```

**Why name resolution and not syntax.** A name that does not resolve is a
*semantic* failure over a *well-formed token stream* — the parser's position is
still exactly right, so there is nothing to resync and no rollback to design.
That is why this slice is safe and the syntax half is not: past a syntax error
the parser's position is meaningless, and continuing produces cascades, which is
the failure mode the ticket itself warns about ("a compiler that limps on
producing cascading nonsense, which is worse than stopping"). A syntax error
still halts, and a recovered diagnostic followed by a syntax one reports both
and then stops — measured.

**The caller owes the parse a stand-in.** `ErrorRecover` returning with the
symbol index still `-1` just moves the crash, so the two halves are one pair of
helpers in `pasparser_lval.inc`: `ReportUndefinedName` (the three-way
diagnostic, which existed in four drifting copies) and `PoisonSym`, which mints
an ordinary Integer variable under the failed name. It is REGISTERED under that
name, so a typo repeated five times is reported once — one line per mistake, not
per occurrence. Nothing poisoned can reach codegen: `ErrCount` is checked before
any emission.

Capped at `MAX_REPORTED_ERRORS = 20`, then `too many errors, stopping`. Past a
handful, a cascading file produces noise rather than information.

**Gate:** `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN; new `test-core` case
`test_two_undefined_names_both_report_fail` asserts all three properties (both
names reported, the repeat silent, no binary written).

### What is left, and it is most of the ticket

- **Item 1 (speculative parse) is NOT delivered.** `ErrorRecover` is the
  *mechanism* a trial parse needs, but the hard half named in "Shape, not a
  prescription" is untouched: what state a failed attempt must unwind. The
  pieces exist — `SymRollbackTo` is already used by six parsers — but nothing
  ties an error to a rollback point yet, and until it does NilPy's typing pass
  still cannot trial-parse a name it has not seen.
- **Item 2 is delivered for names only.** Syntax errors still halt at the first
  one; that is a deliberate boundary, not an oversight.
- **Extending recovery is per-site work with the pattern now established.**
  `class method not found`, `New: undefined variable` and the rest are the same
  shape: report, mint a stand-in, `Exit`. Each one is a judgement about what
  stand-in keeps the parse sane, which is why they were not swept in bulk.

## Slice 2 landed 2026-08-24 (claude-A) — three more diagnostics, and the resync that made them worth having

Slice 1 made `Error()` able to return and converted the four "undefined
variable" sites. Three more name-resolution diagnostics now recover, chosen
because together they cover the ordinary typo:

- **unknown TYPE** (`var x: TUnknwn;`) — stands in `tyInteger`, which is exactly
  what the catch-all used to produce SILENTLY before it was closed. The
  difference, and the whole point, is that it is now reported and the compile
  fails.
- **unknown MEMBER** (`r.nofield`) — the caller falls into `RecFieldType`'s
  not-found default, again the old silent behaviour, now reported.
- **a call to a procedure that does not exist**, which needed something the
  first three did not.

### The resync, and why a stand-in was not enough

`NoSuchProc;` is not an assignment, so a stand-in VARIABLE leaves the statement
parser at `Expect(':=')` and it dies on `unexpected token` — which buries the
real diagnostic under a meaningless one AND stops the file at the first mistake,
the exact thing this ticket exists to prevent. So the statement dispatcher now
takes a **watermark**: if `ErrCount` rose while parsing the statement's lvalue
and what follows is not an assignment operator, it skips to the statement
terminator and yields an empty block.

That is classic panic-mode recovery, and it is safe HERE for the reason slice 1
gave: the token stream is well-formed, so "skip to the next `;`" discards
exactly one statement and lands somewhere real. It is not a general syntax-error
recovery and must not be read as one.

Measured against fpc 3.2.2 on a file with four different unresolved names —
a type, a member, a procedure call, a function in an expression:

```
pascal26:17: error: unknown type: TUnknownType
pascal26:21: error: "nofield": no such member on this record/class
pascal26:22: error: undefined variable (NoSuchProc)
pascal26:23: error: undefined variable (NoSuchFunc)
```

fpc reports the same four (plus a follow-on "Error in type definition" for the
first). Three unresolved names inside expressions across three lines match FPC
name for name and line for line.

### Found while doing it: `ParseLValue` and `CompileLValueAddress` are DEAD

`compiler/pasparser_lval.inc`'s `ParseLValue` has no callers anywhere in
`compiler/**` — only its own forward declaration — and `CompileLValueAddress` is
called only from inside it. Roughly 130 lines of statement-assignment parsing,
including a direct-emit path (`EmitB($48)`) from the pre-AST era, that nothing
reaches. Not deleted here, because "dead" is a claim that deserves its own
change and gate rather than a footnote in someone else's; filed as
[[chore-a-delete-the-dead-pascal-lvalue-statement-path]].

### Still open

Item 1 (speculative parse) is untouched: the mechanism exists, the state-unwind
design does not. Syntax errors still halt at the first one — deliberately.
