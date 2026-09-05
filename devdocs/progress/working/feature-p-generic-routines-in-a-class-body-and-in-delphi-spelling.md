---
slug: feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling
title: "A generic routine is parsed at top level only — not as a class method, and not in the Delphi spelling"
track: P
prio: 45
type: feature
blocked-by: []
status: working
owner: frankA
created: 2026-09-05
summary: "`generic procedure`/`function` at unit level works (71deb21d4). Two adjacent spellings do not parse at all: `generic function Add<T>(...)` declared INSIDE a class body, and the Delphi form `function Add<T>(...)` with no `generic` keyword, both as a free routine and as a method. Eight FPC-testsuite rows, four each, one diagnostic each — measured 2026-09-05, and they are the largest remaining lever in the generics conformance cluster."
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
