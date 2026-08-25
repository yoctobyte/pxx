---
track: A
prio: 45
type: feature
summary: "`Error()` calls `Halt` directly, so nothing in the compiler can trial-parse and back out. That blocks NilPy's type inference (which needs to read an as-yet-unseen name speculatively), and it is also why the compiler stops at the FIRST error. Make the error path recoverable; several unrelated wants fall out of the same change."
status: working
owner: claude-A
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

## Slice 3 landed 2026-08-24 (claude-A) — bad CALLS, and the value-shaped half of recovery

Slices 1 and 2 covered names that do not resolve. The next thing an ordinary
file gets wrong is calls, and it was still halt-at-the-first: measured against
fpc 3.2.2 on a file with four bad calls, fpc reported all four and pxx reported
one.

Both `no overload of X matches these arguments` sites now recover. The reason it
is safe is the one slice 1 gave and it is stronger here: when the mismatch is
detected the arguments **and the closing paren are already consumed**, so the
parser is sitting exactly where a *good* call would have left it. There is
nothing to resync and no rollback to design — the slice-2 statement watermark is
not even needed.

The two sites need different stand-ins, and that distinction is the new thing:

- **statement position** (`pasparser_stmt.inc`) — yield an empty `AN_BLOCK`.
  One call is discarded and nothing else.
- **expression position** (`pasparser_expr.inc`) — an empty statement is not
  available; the caller is mid-expression and needs a **value**. Same poison
  rule as `PoisonSym`: an ordinary Integer `0`, which every enclosing operator
  accepts, so `i := F(1) + F(2, 3)` reports the bad operand and does NOT produce
  a second diagnostic about the `+` that never got one.

Measured after, on the gated test:

```
pascal26:30: error: no overload of Two matches these arguments
pascal26:31: error: no overload of Two matches these arguments
pascal26:32: error: no overload of F matches these arguments
pascal26:33: error: no overload of F matches these arguments
```

fpc reports the same four lines. The correct `Two(1, 2)` at the end stays
silent — recovery that flags good code would be worse than halting — and no
binary is written.

**Gate:** `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN; new `test-core` case
`test_bad_calls_all_report_fail`, and both earlier error tests re-measured
unchanged.

### Found while measuring, and much worse than what was being measured

The same sweep asked what ELSE a file gets wrong, and turned up that **pxx does
not type-check assignments at all**: 17 of 18 assignments fpc rejects with
`Incompatible types` are accepted silently, including `i := s` (prints the
string's heap address) and `s := i` (segfaults). Filed as
[[bug-p-an-assignment-is-not-type-checked-at-all]] at prio 60 — Track P's, and
not folded in here: this ticket is about the error *path*, that one is about a
check that was never written.

### Still open

Item 1 (speculative parse) is untouched, and remains the reason this ticket
stays open: `ErrorRecover` is the mechanism a trial parse needs, but nothing
ties an error to a rollback point, so the state-unwind question in "Shape, not a
prescription" is still unanswered. Syntax errors still halt at the first one,
deliberately.

## Slice 4 landed 2026-08-24 (claude-A) — the four error routines stop being four copies

Not new recovery: the *shape* of what slices 1-3 grew. Adding the fourth entry
point (`ErrorAtRecover`, for the assignment type check) made the pattern
obvious, and it was worth deleting rather than auditing.

`ErrorPrint`'s own comment claimed to be *"the one place a diagnostic is
formatted"* — while `ErrorAt` and then `ErrorAtRecover` each carried their own
copy of the ident-parens logic, and the `MAX_REPORTED_ERRORS` cap was written
out twice. Three copies of one five-line rule, and the third arrived the moment
a fourth entry point was needed. That is
`devdocs/dev/normalise-dont-special-case.md` exactly: the copy is what stays
broken.

The four names are not the problem — they encode **two independent axes**, which
is why there are four and not one:

|  | halt | count and return |
| --- | --- | --- |
| **line = current token** (parser is there; `in:`/`near:` are meaningful) | `Error` | `ErrorRecover` |
| **line = an AST node** (lowering runs past EOF; a `near:` window would point at the end of the program and mislead) | `ErrorAt` | `ErrorAtRecover` |

So the four stay, and now sit on **two** shared helpers instead of four copies:

- `ErrorPrintAt(line, msg, withContext)` — THE one place a diagnostic is worded.
  `withContext` is False for a post-parse check, which is the whole reason the
  bottom row exists.
- `CountRecoveredError` — the tail every recovering diagnostic shares, cap
  included.

`ErrorPrint(msg)` is now one line (`ErrorPrintAt(CurTok.Line, msg, True)`), kept
as its own name because that is what the ~600 `Error()` sites read as.

**Measured.** Self-host fixedpoint converged in one round and the compiler got
**1,565 bytes smaller** (9,037,665 → 9,036,100). All four paths verified to
print exactly what they printed before:

- `ErrorRecover` — `test_two_undefined_names_both_report_fail`: both names, both
  with their `near:` windows.
- `ErrorAtRecover` — the assignment test: 13 diagnostics, no window, correct lines.
- `Error` — a syntax error: message plus `near:` window, halts.
- `ErrorAt` — the enum-identity check: message, no window, halts.
- The shared cap: a file with 25 undefined names reports exactly 20 and then
  `too many errors, stopping`.

**Gate:** `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN.

### Still open, unchanged

Item 1 (speculative parse). `ErrorRecover` is the mechanism; nothing ties an
error to a rollback point, so the state-unwind question in "Shape, not a
prescription" is still unanswered. Syntax errors still halt at the first one,
deliberately.

## Slice 5 landed 2026-08-25 (claude-A) — three diagnostics that were WRONG, not merely early

Slices 1-4 made the error path able to return and converted the name and
overload sites. Slice 5 came from asking the obvious next question — *what else
does an ordinary broken file get wrong?* — as a 28-construct sweep against fpc
3.2.2, one construct per program. Eighteen were diagnosed correctly. Three were
diagnosed **wrongly**, and each also halted, so a file containing any of them
reported nothing else:

| source | pxx before | what it should say |
| --- | --- | --- |
| `P1;` where `procedure P1(x: Integer)` | `undefined variable (P1)` | wrong number of parameters |
| `c.M(1, 2)` on a parameterless method | `Expected: ), but got:` then `unexpected token` | wrong number of parameters |
| `i(3)` where `i: Integer` | `Expected: :=, but got:` then `unexpected token` | i is not callable |

A wrong diagnostic is worse than an early one — it sends the reader to the wrong
place. `undefined variable (P1)` over a name declared eight lines up is the
clearest case, and this repo had already fixed **the other arm of that exact
bug**: `bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable`,
whose note in `pasparser_stmt.inc` reads *"The diagnostic was the misleading
part: the NAME had resolved, the ARITY had not."* That fix taught the
all-defaulted case to work; the case with no default to fill kept the misleading
message. One concept, two arms, one of them fixed — the sibling this repo's own
`normalise-dont-special-case.md` says to grep for.

### The method arm needed a shared tail, because there are seven copies

`c.M(1, 2)` did not die in one place. **Every method-argument loop in the Pascal
frontend is index-driven** — parse exactly `ParamCount` arguments, then
`Expect(tkRParen)` — and there are **seven** of them: one in
`pasparser_call.inc`, four in `pasparser_lval.inc`, two in `pasparser_expr.inc`.
Patching the one the repro happened to hit would have left six.

So the close is one shared tail, `ExpectCallRParen(mpi)`: report the arity, then
swallow the surplus with paren-depth tracking so the parser lands after the `)`
exactly where a good call would have left it. Six call sites replaced, and the
compiler came out **4,582 bytes smaller** (9,054,001 → 9,049,419) — the usual
sign that a consolidation removed real duplication rather than moving it.

### Why all three are safe to recover

The same reason slices 1 and 3 gave, and it holds more strongly here: the token
stream is **well-formed** in every case. `P1;` is a single name and its
terminator. A surplus argument list is consumed to its own `)`. `i(3)` is
resynced to the statement terminator. Nothing is emitted regardless — the driver
halts on `ErrCount` before RTTI, fixups or output.

### Measured

`test/test_bad_arity_and_noncallable_all_report_fail.pas`, gated in `test-core`:
all four mistakes reported in ONE compile, on their own lines, exit 1, no binary
written. fpc 3.2.2 reports the same first three at the same lines and then stops;
pxx reports the fourth as well.

**Gate:** `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN.

### Found by the same sweep, and much worse — filed, not folded in

Ten of the 28 constructs fpc rejects are accepted here with **no diagnostic and
exit 0**, and five of those are not lax, they are wrong: `i[2]` on an Integer
reads out of bounds, `for s := 1 to 3` makes the rest of the program not run,
`New(i)` overwrites an Integer with a heap pointer, `Inc(s)` empties a string,
`Length(i)` answers 1. Filed as
[[bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong]] at prio 55.
Same call as slice 3's assignment finding: this ticket is about the error PATH,
that one is about checks that were never written.

### Still open, unchanged

Item 1 (speculative parse). `ErrorRecover` is the mechanism; nothing ties an
error to a rollback point, so the state-unwind question in "Shape, not a
prescription" is still unanswered — and its only known consumer (NilPy typing)
is deferred, so the ranking argument for doing it now is weak. Syntax errors
still halt at the first one, deliberately.

## Slice 5 landed 2026-08-25 (claude-A) — the file reports its LAST mistake too

Slices 1-4 made recovery possible and converted the name and call sites. This
slice asked the ticket's item-2 question again, with a bigger file, and found
**three** independent reasons a compile still stopped early. Measured against
fpc 3.2.2 on a 15-error file: fpc reported all fifteen, pxx reported **nine**.

### 1. Two more diagnostics that still halted

- **`class method not found`** (`TC.NoSuchMember`) — the metaclass twin of
  `r.nofield`, which slice 2 already recovered. Same well-formed token stream,
  same nothing-to-resync, and it was the halt that killed the file at error 9.
- **`SizeOf: unknown type or variable`** — its stand-in (a size of 0) was
  *already written on the next line*; only the halt had to go. That shape kept
  recurring in this sweep: a diagnostic whose caller already knows what to carry
  on with.

The "report → swallow the argument list → hand back an Integer 0" longhand had
reached its third copy, so it is now `PoisonValueNode`.

### 2. Bodies are lowered AS THEY ARE PARSED, so poison reached codegen

The claim in slice 1 — *"Nothing poisoned can reach codegen: `ErrCount` is
checked before any emission"* — was **wrong**, and the check's placement is why.
It sits after `ParseProgram`, but a routine body is lowered at its own `end`,
inside the parse. So `SetLength(NoSuchArr, 3)` reported the undefined name and
then died on the FATAL `SetLength expects a string variable in IR codegen`,
attributed to the routine's `end` line, taking every later routine's diagnostics
with it. Five undefined names across three routines produced three lines and a
nonsense fourth.

`CompileAST` now returns immediately when `ErrCount > 0`. That is the whole fix
and it is safe by construction in both directions: the compile has already
failed, so there is nothing the emission could still be for; and when `ErrCount`
is 0 the guard is not reached at all, so **the self-host fixedpoint cannot
move**.

### 3. The stand-in produced misleading follow-ons

`PoisonSym` mints an Integer, and an Integer is a fact about the RECOVERY, not
about the program — so any later check that reads its type describes something
the user never wrote. `Length(NoSuchStr)` printed the undefined name AND
`Length needs a string, an array or a PChar, not Integer`; `New(NoSuchPtr)`
added `New needs a pointer variable, not Integer`. fpc prints one line for the
first and says `<erroneous type>` for the second — the same admission, more
honestly worded.

`ASTIsPoisoned(node)` answers whether a value came from a name that did not
resolve, recursing through the operators an enclosing expression can wrap it in
(so `Length(NoSuchVar + 'x')` is quiet for the same reason). The two checks
above consult it. Backed by a LIST of at most `MAX_REPORTED_ERRORS` symbol
indices rather than a per-symbol flag: recovery is capped at twenty, so a linear
scan beats a parallel array over every symbol plus its three init sites.

### Measured

| file | fpc real errors | pxx before | pxx after |
| --- | ---: | ---: | ---: |
| 15 unresolved names/members/calls | 14 lines | 9 | **14** |
| 19 names across statements, calls, casts, control flow | 19 lines | 20 incl. 1 bogus, **cap hit** | **19** |
| 5 names across two routines + main body | 5 lines | 3 + 1 nonsense | **5** |

Line for line with fpc in all three, and no binary is written.

**Gate:** `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN; 141 lib units compile; fpc-testsuite unmoved. New
`test-core` case `test_errors_across_routines_all_report_fail`, whose five
expected lines are the five fpc reports on the same source.

### Still open, unchanged

Item 1 (speculative parse). `ErrorRecover` is the mechanism; nothing ties an
error to a rollback point. Its only known consumer (NilPy typing) is deferred,
so the ranking argument for doing it now is still weak. Syntax errors still halt
at the first one, deliberately.
