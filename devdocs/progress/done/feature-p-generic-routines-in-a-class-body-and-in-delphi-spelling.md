---
slug: feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling
title: "A generic routine is parsed at top level only — not as a class method, and not in the Delphi spelling"
track: P
prio: 45
type: feature
blocked-by: []
status: done
owner: frankA
created: 2026-09-05
summary: "RESOLVED 2026-09-05 (63b699013, 0ee1e272f). Both spellings parse: the Delphi `function Add<T>(...)` as a free routine and, with `generic`, as an instance or class METHOD — one parser and one token-level expansion, nothing added to the class parser, method registrar, VMT builder or call path. Each surface diffed against fpc 3.2.2 OUTPUT. Of the eight rows, tgenfunc2 and tgenfunc4 pass; tgenfunc5/6 parse and compute correctly and fail on a nil receiver pxx refuses by choice; tarray16 needs dyn-array initializers; tgenfunc7/9 (cross-unit) are split out to [[feature-p-a-generic-method-cannot-be-used-from-across-a-uses-clause]] and tgenfunc12 needs two unrelated things."
---

# Two spellings, four rows each, one diagnostic each

Measured against the whole generics cluster of the FPC test suite, so these are
not guesses about what might be missing.

**A — `generic` before a METHOD, inside a class body** (`expected ':' before
'function'`):

```pascal
type TTest = class
  generic function Add<T>(a, b: T): T;    { <- refused here }
end;
```
rows: `tgenfunc5`, `tgenfunc7`, `tgenfunc9`, `tgenfunc12`

**B — the DELPHI spelling, no `generic` keyword** (`expected ':' before '<'`):

```pascal
function Add<T>(a, b: T): T;              { free routine }
type TTest = class
  class function Add<T>(a, b: T): T;      { and as a method }
end;
```
rows: `tgenfunc2`, `tarray16` (free), `tgenfunc4`, `tgenfunc6` (methods)

Both diagnostics are the parser hitting the `<` where it expects a parameter
list or a return type, so nothing downstream has been exercised — this is a
front-end gap, and what lies behind it is unmeasured.

# Why these two together

`71deb21d4` added `generic procedure` / `generic function` at unit level, and
[[bug-p-a-generic-function-cannot-be-declared-in-a-unit]] closed the unit case.
So the CONCEPT exists and the substitution machinery behind it runs; what is
missing is the two remaining positions the same declaration can occupy. That is
`devdocs/dev/normalise-dont-special-case.md`'s shape exactly — one construct
reachable through several spellings, with the later spellings left behind.

Filed as ONE ticket because the fix is likely one: whatever accepts a type
parameter list after a routine name at unit level has to be reachable from the
class-member declaration parser and from the Delphi spelling. If measurement
says they are genuinely two mechanisms, split it then, not now.

# The trap this area already has

**A `%FAIL` row scores ANY refusal as a pass**, and this cluster is full of
them. Making the parser accept a spelling it used to refuse will turn some rows
RED, and those are missing diagnostics that were always missing rather than
regressions — that is exactly how `tgenfunc17`/`tgenfunc18` and `tgeneric4`
became visible. Read the fail list BY NAME after any change here, and check a
newly-passing `%FAIL` row passes for the reason it states.

# Gate

The eight rows above compiling, and each diffed against **fpc 3.2.2 output**
rather than scored on its exit code — the conformance harness compares exit
codes, so a row that runs printing the wrong thing reads as a pass. Plus the
conformance fail list read by name, `make test`, and the self-host fixedpoint.

---

## 2026-09-05 (frankA) — half B, the Delphi FREE routine, is done; and the record it needed could not be a record

`function Add<T>(...)` at top level now parses, in a program and in both of a
unit's sections, and `Add<LongInt>(2, 3)` at a use site specializes it. Measured
against fpc 3.2.2 output, not exit codes: `5` / `HelloWorld` byte for byte on
the tgenfunc2 shape, and `9` / `ab` on a cross-unit one fpc also accepts.

**And the row itself cannot carry that diff.** `tgenfunc2` PRINTS NOTHING — it
`Halt(n)`s on failure and exits 0 otherwise, and the runner's own `directives()`
extractor reports no directive on it, so an output diff of the row is two empty
files: a comparison that cannot fail, which is the shape
[[bug-t-the-conformance-runner-lets-a-caller-read-around-its-own-directive-extractor]]
was filed about the same day. The row's assertion IS its exit code, legitimately,
because its author wrote the check into the program. What was diffed against fpc
is an equivalent program that PRINTS the two values, which is where `5` /
`HelloWorld` comes from. Say which of the two you ran; they are different claims.

**It is one parser, not two.** `ParseGenericFunctionDef` consumes the `generic`
keyword only if it is there, and `IsGenericRoutineHeaderAhead` — a `<` where an
ordinary header has `(` or `:` — is the single place the Delphi form is
recognised, called from all three top-level declaration dispatchers. Adding a
second entry point would have duplicated the token-buffering body, which is the
copy that stays broken.

### Three things worth carrying forward

**1. The USE site is ambiguous and the DECLARATION site is not.** `Add<LongInt>(2, 3)`
is `a < b > (c)` to a parser that does not know `Add`. The gate is that `Add`
was itself declared in the Delphi surface — a per-routine flag, the same shape
`TemplateIsDelphi` already has on the type side — so an objfpc program's
comparisons cannot be eaten. `test_generic_routine_both_spellings.pas` carries a
plain `a < b` as the control for that direction; without it the sweep would be
free to widen and no row would notice.

**2. In the Delphi surface a DECLARATION is spelled exactly like a USE.**
`function UAdd<T>(` in a unit matches the use pattern token for token, and a
unit's tokens are appended AFTER the importing program's, so the program's
forward sweep runs straight over the unit's own headers. Before the guard they
were rewritten to `UAdd_T` and compiled as real routines — the diagnostic was
`unknown type: T`, reported inside the unit, from a defect in the program's
sweep. `function`/`procedure` immediately before the name is the whole
discriminator. The objfpc surface never had this because a declaration has no
`specialize` keyword. Permanent row: `test/generic_func_unit_units/ugfdelphi.pas`.

**3. `TGenericFunc` cannot grow a field.** The obvious home for the flag is the
record, and it does not fit: `TGenericFunc` is a BUILT-IN record whose layout is
hard-coded in `symtab.inc`'s `REC_TGENERICFUNC` table and baked into the
compiler BINARY, so the compiler that precedes the change cannot compile it.
Measured: with the declaration, the field table, the field-count, the type map
and the size assertion all updated together and all agreeing with each other,
round 0 of the fixedpoint still answers `"IsDelphi": no such member`. A parallel
array is the established answer — `GenericFuncSrcKey` sits beside it for the
same record, and `SymTR`'s declaration comment records the same finding for
`TSymbol`. **The `near:` window pointed at an unrelated line**, which is the
usual shape: it names where the parse was, not where the error is.

### What is left, and what it is worth

Half B's other row, `tarray16`, is NOT unblocked by this: its skip reason names
two gaps and the second one — dynamic-array const initializers `[1, 2, 3]` — is
untouched. So the Delphi free routine closes **one** conformance row, not two,
and the honest count for this half is one row and one mechanism.

### The one row this turned red, and it was mine

The ticket body predicted that accepting a spelling pxx used to refuse would
turn `%FAIL` rows red and that those would be *"missing diagnostics that were
always missing"*. That prediction was wrong for `tgeneric31`, and reading the
fail list by NAME is the only reason that is known.

`tgeneric31` is `{ %fail }` — lower case, the disguise
[[bug-t-the-conformance-runner-lets-a-caller-read-around-its-own-directive-extractor]]
is about — and it went from pass to `accepted-invalid` under this change. Its
body is a mode-Delphi generic class whose method implementation header names
ONE type parameter where the class declared two:

```pascal
type TGenericClass<T1,T2> = class ... end;
function TGenericClass<T1>.DoSomething(Arg: T1): T1;   { fpc refuses this }
```

The first spelling of `IsGenericRoutineHeaderAhead` tested for `function` ident
`<` — and that is a generic class's method header too. So a header pxx used to
refuse was handed to the ROUTINE parser, which read the class name as a routine
name and accepted it. Not a missing diagnostic: a diagnostic this change
removed.

**The fix is what CLOSES the group, not the group.** A generic routine's type
parameter list is followed by `(`, `:` or `;`; a generic class's is followed by
`.` and a method name. One token of lookahead past the `>`.

**And the control refused the obvious story.** The comment first written beside
the fix said the loose predicate *"would have swallowed every VALID Delphi
generic-class method header as well"*. Built with the loose predicate on purpose
to check: an ordinary `TBox<T>` with `function TBox<T>.Echo`, specialized and
called, **still compiled and still printed fpc's answer**. The loose test only
misfires on a class that is never specialized — the specialized case is
desugared before this dispatcher runs and is immune by coincidence. That is why
no corpus row and no test in `test/` caught it, and why the only witness in 550
rows is a program that declares a generic class and does nothing with it.
`test_generic_routine_both_spellings.pas` now carries that shape as a permanent
row, since the population that would otherwise notice cannot.

### The numbers, and they reconcile

| | before | after |
| --- | --- | --- |
| pass | 371 | **372** |
| fail | 3 | 3 |
| skip | 142 | **141** |

`tgenfunc2` unskipped and passes; `tgeneric31` went red and came back once the
predicate was tightened; the three that remain (`tgeneric4`, `tgenfunc17`,
`tgenfunc18`) are the pre-existing `accepted-invalid` rows from the tight-`>=`
work and are unmoved by this. **The pass count moving by one is not the
finding** — a `%FAIL` row is a pass by refusal, so this cluster's count says
nothing on its own; the fail list read BY NAME is what caught tgeneric31, and a
count would have shown 371 → 371 and looked like nothing had happened.

---

## 2026-09-05 (frankA) — half A, the METHOD positions, both surfaces

`generic function Add<T>` inside a class body and the Delphi `function Add<T>`
both parse now, as instance methods and as class methods, with the definition
written `[generic] [class] function TTest.Add<T>` and the call written
`t.specialize Add<C>(..)` or `t.Add<C>(..)`. Diffed against **fpc 3.2.2 output**
per surface (fpc cannot hold both in one compilation): `5 / HelloWorld / 42 /
abab` byte for byte on each.

**It is not a new kind of member.** `ExpandGenericMethod` rewrites the three
halves — declaration, definition, uses — into one ORDINARY method per concrete
type argument, in the token stream, before the class-body parser sees any of it.
Afterwards the stream says `function Add_Integer(..): Integer;`,
`function TTest.Add_Integer(..)` and `t.Add_Integer(..)`, which every path below
already handles. Nothing was added to the class parser, the method registrar,
the VMT builder or the call path. That is the same sweep-then-emit shape the
free routine has had since `71deb21d4`, which is why this was one normalisation
job and not two features.

### The rows, and what each one actually needs

| row | state |
| --- | --- |
| `tgenfunc4` | **passes** — Delphi class function. Unskipped. |
| `tgenfunc5` | parses and computes correctly; **the row never `Create`s its receiver** |
| `tgenfunc6` | same, Delphi surface |
| `tgenfunc12` | halves parse (incl. the `<T: class>` constraint); needs `.Free` on a method RESULT and a free `specialize F<C>;` with no argument list |
| `tgenfunc7`, `tgenfunc9` | cross-unit — deliberately out of scope, see below |

**`tgenfunc5` and `tgenfunc6` are not blocked by anything in this ticket.** Both
declare `var t: TTest;` and never construct it, then call an instance method on
that nil reference. fpc runs it — `Self` is nil and the body never touches it —
and pxx raises `Runtime error 216 (nil reference)`. Measured to be **pre-existing
and unrelated to generics**: an ordinary non-generic instance method on a nil
receiver does exactly the same on pin v403, while fpc prints the answer. Adding
a single `t := TTest.Create;` makes both rows exit 0, which is the measurement
that separates "the feature does not work" from "the row is written this way".

By `CLAUDE.md`'s *on par with the LANGUAGE, not with FPC* rule this divergence is
**chosen, not tolerated**: a method call on an uninitialised object reference is
only produced by a mistake, and pxx's answer is the one that leaves the mistake
visible. So those two rows are `wontfix:`, with the reason recorded in
`pxx.skip` rather than in a ticket nobody will read.

### The limit, stated as a limit and not as an oversight

Every edit the expansion makes is at or ABOVE the class body, and it bails out
entirely if any use site sits below. A use below the declaration is exactly what
a program calling a USED UNIT's generic method looks like — a unit's tokens are
appended after the program's — and moving edits below the cursor would need
`TokPos` and every recorded `DeclItem` span moved with them, while
`AdjustPass2Spans` is a no-op outside the body pass. `tgenfunc7` and `tgenfunc9`
are that shape and stay skipped, with the reason on the row.

### Two defects the tests found and reading would not have

**1. A use site names a METHOD, not a class.** With two classes declaring `Add`,
the definition header `function TDelphi.Add<T>` is `.`-prefixed and matched the
use pattern token for token, so it was read as a use of `TObjFpc.Add` with the
concrete type `T` — the expansion emitted `Add_T` and answered `unknown type: T`
on the definition. Excluding this method's own header by index was not enough;
the discriminator is the SHAPE that makes a header a header (an ident and a
`function`/`procedure` behind the dot).

**2. And the same fact bites again at the rewrite.** The first class to expand a
name rewrites every use of that name, including the other class's, so the second
expansion found nothing left and would have silently left its own generic
declaration in the stream. The set is remembered by NAME and read back
(`GMSpecMeth`). It over-approximates on purpose: emitting a method nobody calls
is dead code, not emitting one is a program that does not compile, and the
over-emission only happens for a name two classes share — which is exactly the
case that otherwise cannot work at all.
`test_generic_method_both_spellings.pas` carries two same-named methods for
this reason and is the only thing that exercises it.

### One defect the tests did NOT find, and how it showed

The rewritten use token got its new text but not its SPELLING CHANNEL, so
`TokSrcOff`/`TokSrcLen` still pointed at the original source range: the `near:`
window printed `t . Test . Free` while the token was `Test_TObject`. **A
diagnostic naming an identifier that is no longer there** — nothing fails, the
window just lies, and it was only visible because a row that still errors made
me read one. `SpecializeToBuffer` clears both fields for every token it
rewrites; the two hand-rolled rewrites (this one and the free routine's, which
had the same omission since it was written) now do too.

### The row this turned red, and why it stays red

`tgenfunc14` — `{ %FAIL }`, a UNIT, asserting *"constraints must not be repeated
in the definition"* — went from pass to `accepted-invalid`. It is this change's
doing and the reason is worth stating precisely, because "pxx used to refuse it"
is true and misleading.

pxx refused it by refusing CONSTRAINTS ENTIRELY: `generic procedure Test<T: class>`
in a unit interface hit the `:` and came out as *"unexpected token in a unit
interface section"* — a syntax refusal, not the rule the row is about. Isolated
through the runner's own synthesized driver (`program drv; uses tgenfunc14;`),
which is the only way to reach it since pxx has no standalone-unit output and
BOTH compilers refuse the file directly with the same unit message: **pin
refuses, this build accepts.** fpc, compiling it properly as a unit, says
`function header doesn't match the previous declaration "Test$1;"`.

**Keeping the constraint change is still right, and it is not paid for by
tgenfunc12** — which still does not pass. `generic function F<T: class>: T` is
valid Pascal that pxx answered with `expected '>' before ':'`, and refusing
valid code that real generic code writes is the worse of the two errors.
Accepting a REDUNDANT constraint is `CLAUDE.md`'s *"us accepting what FPC rejects
is not a defect"*, and pxx does not check constraints at all, so the rule has no
correctness value here.

It is left RED rather than skipped with `accepts-invalid:`, to sit with
`tgeneric4`, `tgenfunc17` and `tgenfunc18` — the same family, the same
disposition. Whoever decides that these four should stop occupying a permanently
red list can move all four together; doing it for mine alone would hide the one
row a reader has the most reason to check.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 46aac96a3.
