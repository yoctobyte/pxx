---
track: A
prio: 75
type: feature
blocked-by: []
summary: "SUPERSEDED BY THE SIBLING DESIGN AT THE END — no hook needed. Also FIXES bug-nilpy-exception-repr-and-type-name-say-pyexception by construction. One Exception class in a shared builtin unit, re-exported by BOTH sysutils and pylib under their own names (`type Exception = exceptions.Exception`). Retires the catch bridge, the layout guard and the shared-name history in one move. Every mechanism verified 2026-08-14; the only member that does not merge cleanly is CreateFmt, and the hook that solves it is measured to work."
status: working
owner: agent-an
---

# One `Exception`, declared once, re-exported by both units

User's design, 2026-08-14. Supersedes the arrangement built earlier the same day
([[decide-pylib-exception-vs-sysutils-exception]] option 5, which renamed pylib's
root to `PyException` and bridged the two in the `except` lowering).

```pascal
unit exceptions;                    { compiler/builtin/ — pylib cannot reach lib/rtl }
interface
type
  Exception = class
  public
    msg: AnsiString;
    argsv: TObject;                 { Python payload, UNTYPED on purpose — see below }
    constructor Create(const m: AnsiString);
    constructor CreateFmt(const m: AnsiString; const args: array of const);
    property Message: AnsiString read msg write msg;
    ...
  end;
```
```pascal
unit sysutils;                      unit pylib;
uses exceptions;                    uses exceptions;
type                                type
  Exception = exceptions.Exception;   PyException = exceptions.Exception;
  EConvertError = class(Exception)    ValueError = class(PyException) end;
```

## Why this beats what is in the tree today

One row, two names. `except Exception:` catches everything because there IS one
root, so **all three of these come out**: `PyBridgeRootCi` and its `msg`-must-be-
first layout contract, the bridge arm in `PyParseTry`, and the reason
[[bug-nilpy-except-tuple-binder-is-typed-by-the-first-arm-only]] has a
cross-hierarchy case at all.

It also does NOT bring back the constraint that started this. "pylib can never
add a member sysutils lacks" existed because two DIFFERENT classes shared a
name and pylib's bodies bound to the wrong row. With one row, adding a member is
one declaration everyone sees.

## Verified 2026-08-14 — every mechanism, measured

| claim | result |
| --- | --- |
| two aliases in two units resolve to ONE row | yes — a handler on either name catches the other's raise |
| `type Exception = exceptions.Exception` (same name, qualified target) | works |
| `type X = type Y` for a class | **parse error** — and it would have made a DISTINCT type, i.e. today's bug again. Do not use it |
| `ClassName` through an alias | reports the DECLARED name — so the shared class must be NAMED `Exception`, or every Python `repr(e)` prints `ExceptionBase('x')` |
| a consumer naming only sysutils still sees `Exception` | yes, and **also under `--strict-uses`** — the alias is declared in sysutils' own interface, so the name belongs to sysutils and does not depend on interface-section re-export |
| untyped `argsv: TObject` payload, cast inside pylib | yes — pylib reads its own object back; an RTL raise reads nil |

## The one member that does not merge: `CreateFmt`

Two bodies today and only one class can have one: pylib's does minimal `%s`/`%d`
substitution (it must not depend on sysutils, which drags the whole RTL into
every `.npy`), sysutils' calls FPC `Format` and PADS. FPC parity says Pascal
keeps the padding (`Exception.CreateFmt('[%5d]',[3])` -> `[    3]`), so the
minimal body cannot simply win.

**Measured, so the design is not a guess:**

- a procedural type taking `array of const` is **NOT expressible** — the obvious
  hook does not compile;
- a pointer+count hook **does** work: `@a[0]` on an open `array of const`
  parameter, walked as `PVarRec` with `SizeOf(TVarRec)` stride, reads correct
  `VType`/`VInteger`.

So:

```pascal
type TExcFmtFn = function(const f: AnsiString; argp: Pointer; argn: Integer): AnsiString;
var  ExcFmtHook: TExcFmtFn;          { nil => the minimal substituter, moved here from pylib }
```

`sysutils` splits its existing `Format` into `FormatPtr(fmt, argp, argn)` with
`Format(fmt, args)` as a one-line wrapper, and its `initialization` assigns
`ExcFmtHook := @FormatPtr`. Result: **one formatting body per surface, no
duplication** — a Pascal program gets FPC padding, a bare `.npy` with no
sysutils gets today's minimal substitution, and nothing is copied.

`initialization` sections are supported (`lib/rtl/atexit.pas`,
`palthreadobj.pas`, `random.pas` use them).

## Work

1. `compiler/builtin/exceptions.pas` — the class, the minimal formatter moved
   out of pylib, the hook variable.
2. `pylib` — `uses exceptions`, `PyException = exceptions.Exception`, re-root
   its 26 builtin exception classes, reach `argsv` through the untyped slot.
   Its own `Exception` declaration and both constructor bodies come out.
3. `sysutils` (**Track B file — coordinate**) — `uses exceptions`, the
   same-name alias, `Format` split into `FormatPtr` + wrapper, `initialization`
   installs the hook. Its `Exception` declaration comes out.
4. Delete `PyBridgeRootCi`, the bridge arm in `PyParseTry`, and the
   `msg`-must-be-first notes in both units.
5. The pylexer `Exception` -> `PyException` mapping becomes a no-op (one row
   either way). Keep it or drop it — keeping it costs nothing and preserves
   `su.Exception` as a distinguishable spelling.
6. `compiler/builtin/**` changes, so: `stabilize-fast` + `make pin`.

## Gate

`test_uses_order_pylib_exception_a`/`_b` identical and still `[    3]` (the
padding is what proves the hook installed), `test_nilpy_rtl_exception_surface`,
`test_nilpy_pyexception_bare_vs_qualified`, `test_nilpy_exception_args`,
`test_nilpy_exception_non_string_argument` all green, plus a `.npy` with NO
sysutils anywhere confirming the minimal formatter still runs. Self-host
byte-identical.

## 2026-08-14 — two variants MEASURED and rejected; the hook stands

**Variant A (user's simplification): let sysutils INHERIT the root and add
`CreateFmt` to the descendant**, avoiding the hook and the `Format` split
entirely. It does not work, and it fails on the very thing this ticket exists to
remove:

- `class(exceptions.Exception)` — a QUALIFIED base class — is a parse error
  here (`base type not found: excroot`). So the base must be named by a
  bare identifier, which means the root needs a second name.
- With the root named `Exception` and sysutils' descendant ALSO named
  `Exception`, a program that uses sysutils resolves `Exception` to the ROOT
  (registered first, first-match wins) and `Exception.CreateFmt` reports
  *"class method not found"*. **Two classes, one name — the original bug.**

**Variant B: name the root `ExceptionBase`** so the descendant can be
`Exception`. No collision, but pylib's alias then reports `ExceptionBase` as
`ClassName`, i.e. [[bug-nilpy-exception-repr-and-type-name-say-pyexception]]
again with a different spelling. `repr()` follows the DECLARED name and there is
only one declared name to give it.

So the constraint is tighter than it looks: **the class that pylib reaches must
itself be named `Exception`**, which forces sysutils to share that exact class
rather than descend from it — and therefore forces `CreateFmt` onto the shared
root, and therefore the hook. The hook is measured to work (pointer+count; a
procedural type taking `array of const` is not expressible).

Both variants were worth trying — the hook is a real cost and A would have
avoided it. It just cannot hold the name.

## 2026-08-14 — VARIANT C (user): BOTH units declare their own `Exception` under a shared base. This is the design.

```pascal
unit exceptions;                     { compiler/builtin/ }
type ExceptionBase = class  msg: AnsiString;  argsv: TObject;  ... end;

unit sysutils;                       unit pylib;
uses exceptions;                     uses exceptions;
type                                 type
  Exception = class(ExceptionBase)     Exception = class(ExceptionBase) end;
    constructor CreateFmt(...);        ValueError = class(Exception) end;
  end;
  EConvertError = class(Exception)
```

Two classes named `Exception`, siblings under one root. Measured, all of it:

| claim | result |
| --- | --- |
| a handler on `ExceptionBase` catches an RTL raise | yes — `cls=EConvertError` |
| ...and a pylib raise | yes — `cls=ValueError` |
| `ClassName` of pylib's root | **`Exception`** — fixes [[bug-nilpy-exception-repr-and-type-name-say-pyexception]] |
| `ClassName` of sysutils' root | `Exception` |
| sysutils keeps its own `CreateFmt` with the real `Format` body | yes |

**The hook is not needed.** `CreateFmt` lives on sysutils' own descendant, where
`Format` is already in scope — so the `Format` split, the pointer+count
callback and the `initialization` ordering all come out of the plan. That was
the entire cost of the previous variant.

**What replaces the catch bridge:** a NilPy bare `except Exception:` binds
**`ExceptionBase`**, the common ancestor, instead of listing two classes.
One class in the arm, so the shared-binder hazard cannot arise — `e.msg` /
`e.args` resolve on the root by INHERITANCE, at one offset, for every
descendant. `PyBridgeRootCi` and its layout contract still come out, and now
they are replaced by a type relation rather than by another check.

Note the asymmetry, which is deliberate: in `.npy` source `Exception` means
pylib's class in a CONSTRUCTOR position (`raise Exception(...)`,
`class E(Exception)`) so `repr` is right, and the common root in an `except`
ARM so it catches everything. That is what "catches all exceptions" honestly
means once the RTL has its own tree.

### The one residual, measured

For PASCAL code that names BOTH units, the unqualified `Exception` is
uses-order dependent:

| order | bare `Exception` | `Exception.CreateFmt` |
| --- | --- | --- |
| `uses sysutils, pylib` | sysutils' | works |
| `uses pylib, sysutils` | pylib's | **compile error: class method not found** |

That is ordinary Pascal name-collision behaviour — two units exporting one name,
resolved by scope — and `--strict-uses` makes it well defined per unit. It is
NOT the original bug: that one had pylib's OWN method bodies binding to
sysutils' row and losing `msg`, which cannot happen now because each unit's
`Exception` is its own class and `msg` is inherited. The failure mode moved from
a silent wrong body to a compile error.

`test_uses_order_pylib_exception_a`/`_b` change meaning again: they should
qualify (`sysutils.Exception` / `pylib.Exception`) and assert that each unit's
surface works in either order, which is the property that actually matters.

### Open implementation detail: how NilPy names ITS `Exception`

Under variant C, pylib's class is named `Exception` — that is what fixes
`repr`. But then the 18 by-name lookups in `pyparser.inc` cannot use
`FindUClass('Exception')`: that is a FLAT first-match, and in a `.npy` that also
pulls sysutils it can answer with sysutils' class, order-dependently. This is
the same residual as the Pascal side, except here it would be silent rather than
a compile error, so it must be closed rather than accepted.

**Use `FindUClassInUnit('Exception', <pylib>)`** — the helper already exists
(`compiler/symtab.inc`, added for qualified class references). NilPy's
`Exception` then means pylib's class BY CONSTRUCTION, whatever else is loaded,
and the except-arm's root binds `ExceptionBase` resolved in the exceptions unit
the same way. Two precise lookups instead of two ambiguous ones.

**Consequence: the pylexer `Exception` -> `PyException` mapping comes OUT.**
It exists only because pylib's class had a different name; once the class is
named `Exception` and the lookup is unit-scoped, the rename has nothing to do
and would in fact break the lookup. Deleting it also removes the
"maps in, never maps out" asymmetry that caused the repr regression in the first
place — worth stating plainly, because that asymmetry is the actual lesson here.

Open question for whoever builds it: what `except su.Exception:` should mean
once the qualifier is honoured. Today the qualifier is CONSUMED and the member
name resolves flat (`PyParseTry`: *"Unit scope is flat, so the member name alone
resolves; the qualifier just has to be consumed"*), so the qualified form is
already imprecise and `test_nilpy_pyexception_bare_vs_qualified` passes for a
weaker reason than it appears to. Deciding that is part of this work, not
separate from it.

## 2026-08-14 — VARIANT C BUILT AND MEASURED. Parked on ONE prerequisite.

Built in full and verified. Parked, not abandoned — the work is on the branch
`wip/exception-sibling-design` (single commit, master untouched), and the
diagnosis below is why it did not land.

### What the design delivers, measured against CPython and byte-identical

- `repr(e)` is `Exception('plain')` and `type(e).__name__` is `Exception`, so
  [[bug-nilpy-exception-repr-and-type-name-say-pyexception]] is fixed **by
  construction** rather than by adding a second rename. Confirmed for
  ValueError, KeyError (including the raw-key `args`), a user
  `class MyErr(Exception)`, and `ValueError(42).args[0] + 1`.
- The RTL bridge still works: a bare `except Exception:` catches
  `su.StrToInt('abc')`.
- `gate.sh quick` GREEN, self-host converges.

The shape built was exactly variant C: `compiler/builtin/exceptions.pas`
declaring `ExceptionBase` with `msg`, `FHelpContext` and an untyped
`argsv: TObject`; pylib's root renamed to `Exception` and re-rooted; the
pylexer `Exception` -> `PyException` rename DELETED; every by-name lookup in
pyparser routed through a new `PyLibExceptionCi` that uses
`FindUClassInUnit('Exception', pylib)`.

### The prerequisite, and the ticket's own prediction was WRONG about it

This ticket's residual section says the Pascal-side collision surfaces as
*"compile error: class method not found"* and calls that acceptable, because
"the failure mode moved from a silent wrong body to a compile error".

**Measured: it does not. It is still a silent wrong value.** With `uses pylib,
sysutils`:

| expression | expected | actual |
| --- | --- | --- |
| `Exception.Create('pylib hi').Message` | `pylib hi` | garbage bytes |
| `sysutils.Exception.Create('su hi').Message` | `su hi` | garbage bytes |
| `sysutils.Exception.CreateFmt('[%5d]',[3])` | `[    3]` | `[%5d]` (pylib's minimal formatter) |
| `on ex: Exception do` around `StrToInt('abc')` | caught | **UNCAUGHT** — `Unhandled exception: EConvertError` |

Note the second and third rows: **the QUALIFIED form does not disambiguate
either.** That is the part the ticket did not anticipate. Its own note that
"the qualifier is CONSUMED and the member name resolves flat" was recorded as
an imprecision in the NilPy `except` path; it is in fact the general behaviour
of qualified CLASS references, which makes the Pascal escape hatch nonexistent
rather than merely awkward.

So shipping variant C as-is would trade one silent-wrong-value bug for another,
in a configuration that has a regression test precisely because it was a real
bug once. `test_uses_order_pylib_exception_b` catches it, and rewriting that
test to accept the new behaviour would be rewriting a test to bless a silent
wrong value.

### What must land FIRST

**Qualified class references must resolve by unit.** `ConsumeUnitQualifier`
already yields `qUnit` and the symbol/proc lookups honour it
(`FindSymInUnit`/`FindProcInUnit`/`MatchProcCallInUnit`); class lookups do not,
and `FindUClassInUnit` already exists to do it.

Attempted and NOT sufficient: scoping `ctorCi := FindUClass(name)` at
`compiler/parser.inc` (the `X.Create` factor branch) to
`FindUClassInUnit(name, qUnit)`. Rebuilt and re-measured — output unchanged, so
a qualified constructor reaches a DIFFERENT path than that branch. **That is
where the next session starts: find which path `sysutils.Exception.Create(..)`
actually takes.** Do not re-derive the rest; it is all above.

Once qualified references resolve, the two `test_uses_order_pylib_exception_*`
tests become what this ticket already prescribes — qualify both names, assert
each unit's surface works in either uses order — and that is then a real
property rather than an accommodation.

The BARE `Exception` under `uses pylib, sysutils` stays genuinely ambiguous
even then. That one is ordinary Pascal name-collision behaviour and is
defensible, but it deserves a diagnostic rather than first-match silence; worth
its own ticket when this lands.

### Correction to the dead end above — the ctor fix may have been RIGHT and untestable

Re-reading the failing probe rather than the parser: the test that declared it
insufficient could not have shown it working.

```pascal
var se: sysutils.Exception;              { <- resolves FLAT, in TYPE position }
begin
  se := sysutils.Exception.Create('su hi');
  WriteLn(se.Message);
```

`se`'s declared TYPE is resolved by a different path from the constructor, and
that path is still flat — so `se` is statically pylib's class whatever the
constructor built. Under variant C pylib's `Exception` inherits `msg` from
`ExceptionBase` while sysutils' declares its own, so the two are at DIFFERENT
offsets, and reading `.Message` through the wrong static type yields garbage
even when the object is correct. The garbage was evidence about the variable's
type, not about the constructor.

So "scoping ctorCi is not sufficient" is right, but for a reason that changes
the work: **it is not that the constructor takes another path — it is that
qualified class references need scoping in TYPE position too**, and the
constructor fix cannot be observed until they both are.

Next session, in order:
1. Scope qualified class refs in TYPE position (var/field/param declarations,
   `ParseTypeKind`'s class lookup) with `FindUClassInUnit(name, qUnit)`.
2. Keep the `ctorCi` change from the branch — it is probably already correct.
3. Re-run the probe. It only becomes a valid instrument once (1) lands.
4. THEN judge whether the qualified form disambiguates, and only then decide
   about the bare-name ambiguity.

Recorded because the previous entry would have sent the next session hunting
for a parse path that is very likely not the problem — the sort of plausible
wrong root cause `devdocs/dev/root-cause-over-microfix.md` exists to catch, and
it was one re-read away rather than one experiment away.

### The type-position site, located — and it DISCARDS the qualifier on purpose

`compiler/parser.inc`, ParseTypeKind's identifier arm:

```pascal
{ Unit-qualified type reference — `sockets.Tin6_addr` ... Types live in one
  global table, so the qualifier only disambiguates the parse, not the lookup. }
if (CurTok.Kind = tkIdent) and (ConsumeUnitQualifier(lo) <> -1) then
  ;   { lo is now the member name; CurTok sits on it }
```

The unit index is computed and **thrown away** — the empty statement is the
whole handler. The sibling CLASS-qualified branch just below says the same
thing ("the qualifier disambiguates the parse, not the lookup"), and so does
the NilPy `except` path. That invariant — *type names are globally unique, so a
qualifier is only punctuation* — is the actual thing variant C breaks, and it is
stated identically in at least three places rather than being an oversight in
one.

So the work is: capture that return value and thread it to the class lookup in
the same arm, alongside the `ctorCi` change already on the branch. Both are
small; what was missing was knowing they are ONE change, not two, and that the
invariant being revised is written down and load-bearing elsewhere.

Not attempted here: on `master` there is only one `Exception`, so the change is
unobservable and would be an unverifiable edit to shared parser files. It is
testable only on top of variant C, i.e. on the branch.

### The type-position fix was APPLIED and TESTED. It does not work either.

Threaded `ConsumeUnitQualifier`'s return value through ParseTypeKind's
identifier arm into both class lookups (`tkQUnit`, `FindUClassInUnit(lo,
tkQUnit)` with a flat fallback). Self-host converged; on the branch as
`wip(A): thread unit qualifier into ParseTypeKind class lookup`.

Output UNCHANGED — `var pe: pylib.Exception` / `var se: sysutils.Exception`
still both resolve to the same class:

```
py: p`X.t|p`X.t          su: .`X.t          fmt: [%5d]
```

So `var x: unit.Class` does not reach ParseTypeKind's qualified arm at all.
Both fixes attempted so far (ctorCi, ParseTypeKind) were aimed at sites that
are not on the path a qualified class reference actually takes, which means
**the path is still unlocated** and neither the ticket's guesses nor mine have
found it.

That is the honest state after three attempts. Whoever picks this up should
NOT try a fourth site by inspection — instrument instead: `PXXDBG` a print at
each candidate resolution site, compile the two-line repro, and see which one
fires. Reasoning about this parser has now been wrong three times, which is the
signal `devdocs/dev/debugging-playbook.md` names explicitly — measure, do not
reason.

Repro, on top of variant C:

```pascal
program q; uses pylib, sysutils;
var se: sysutils.Exception;
begin se := sysutils.Exception.Create('x'); WriteLn(se.Message); end.
```
Expected `x`; prints garbage.

### INSTRUMENTED. The path was right all along — the INDEX SPACE is wrong.

One probe, and it overturns the previous three entries:

```pascal
if PxxDbgEnabled('a.qual') then
  WriteLn('PXXDBG a.qual TYPEARM lo=', lo, ' qunit=', tkQUnit);
```
```
PXXDBG a.qual TYPEARM lo=Exception qunit=46
PXXDBG a.qual TYPEARM lo=Exception qunit=292
```

So ParseTypeKind's identifier arm **IS** on the path, it **IS** reached for
`var se: sysutils.Exception`, and `ConsumeUnitQualifier` **DOES** hand back a
unit index — a different one for each of the two declarations, exactly as it
should. Every "this site is not on the path" conclusion above is WRONG.

What is left is the only remaining possibility: `FindUClassInUnit(lo, tkQUnit)`
returns -1 and the flat fallback answers, which means **the integer
`ConsumeUnitQualifier` returns is not in the same index space as
`UClsUnitIdx`**. `UClsUnitIdx` holds a `Strs[]` index (CurrentUnitIdx at
parse). `PyLibExceptionCi` works because it builds its argument with
`FindUnitOrAlias`, which evidently agrees with `UClsUnitIdx`;
`ConsumeUnitQualifier` evidently does not.

**Next step is now a one-line check, not a hunt:** print
`FindUnitOrAlias('sysutils')` beside `tkQUnit` at that same probe. If they
differ, the fix is to convert (or to have ConsumeUnitQualifier return the
Strs index), and both the `ctorCi` and ParseTypeKind changes already on the
branch become correct as written.

The lesson is the one the playbook states and I ignored for three rounds: the
expensive bugs here do not crash, they produce a plausible wrong value far from
the cause, and reasoning about which site is on the path lost three times to a
single WriteLn. The probe cost one rebuild.

### Second probe: the index spaces AGREE and the type fix WORKS. The defect is downstream.

```
lo=Exception qunit=46  foa_su=292 foa_py=46  inunit=26 flat=26
lo=Exception qunit=292 foa_su=292 foa_py=46  inunit=86 flat=26
```

Read it line by line, because it settles three questions at once:

- `qunit` matches `foa_py` (46) on the `pylib.Exception` declaration and
  `foa_su` (292) on the `sysutils.Exception` one. **The index spaces agree** —
  the previous entry's hypothesis is wrong.
- `inunit` gives **26** for pylib and **86** for sysutils: two different
  classes, correctly distinguished.
- `flat` gives **26** for both — that is the bug, and the ParseTypeKind fix on
  the branch already avoids it.

So the type-position fix is CORRECT and working. `var se: sysutils.Exception`
now resolves to sysutils' class. The garbage output therefore comes from
somewhere downstream of the variable's type — the constructor being the
obvious candidate, since `sysutils.Exception.CreateFmt('[%5d]',[3])` still runs
pylib's minimal formatter.

**Where the next session starts:** put the same probe at the `ctorCi` site
(`compiler/parser.inc`, the `X.Create` factor branch) and print `qUnit`,
`FindUClassInUnit(name, qUnit)` and `FindUClass(name)`. Either `qUnit` is -1
there — meaning the qualifier is consumed on a different route for a ctor
receiver than for a type — or it resolves and something later re-resolves the
class flat. One rebuild answers it, exactly as the last two did.

Running score of this hunt, kept deliberately: three conclusions reached by
reading the parser, all three wrong; two probes, both decisive.

### Third probe: BOTH fixes work. The residue is METHOD resolution, not class resolution.

Probe at the `ctorCi` site, last two lines of the repro:

```
CTOR name=Exception qunit=46  inunit=26 flat=26 -> ctorCi=26   (pylib.Exception)
CTOR name=Exception qunit=292 inunit=86 flat=26 -> ctorCi=86   (sysutils.Exception)
```

`flat` answers 26 for both — the bug. `inunit` answers 26 and 86 — correct. And
`ctorCi` now follows `inunit`, so **the constructor fix on the branch works**,
exactly as the type-position one does.

So qualified CLASS resolution is solved, in both positions, and the two branch
commits are correct. What is still wrong is narrower than this ticket has
assumed throughout: `sysutils.Exception.CreateFmt('[%5d]',[3])` still prints
`[%5d]`, i.e. pylib's minimal formatter, even though the class resolved to 86.
**Method resolution on an already-resolved class is a separate lookup and is
still flat.**

That is the next probe, and it is the same shape: instrument wherever
`CreateFmt` is matched against `ctorCi`, print the class index it searched.

Corrected picture of the whole hunt:

| attempt | conclusion at the time | actually |
| --- | --- | --- |
| ctorCi scoping | "not on the path" | correct, unobservable alone |
| ParseTypeKind scoping | "not on the path" | correct |
| index-space mismatch | "the spaces disagree" | they agree |
| — | — | class resolution SOLVED; method lookup is the residue |

Three reasoned conclusions, all wrong; three probes, all decisive. The two
fixes were right the first time and the measurements that said otherwise were
each reading a different downstream failure.

### FOURTH probe — the two fixes WORK. The residue is PROPERTY/method lookup only.

```pascal
program q4; uses pylib, sysutils;
var se: sysutils.Exception;
begin se := sysutils.Exception.Create('su hi'); WriteLn('msg=[', se.msg, ']'); end.
```
```
msg=[su hi]
```

Correct. Every earlier probe read `.Message` — a PROPERTY — and got garbage;
reading the FIELD `.msg` on the identical program works. So:

- qualified class resolution: **FIXED**, both positions, by the two commits on
  the branch;
- field access through the resolved class: **correct**;
- **property and method lookup on the resolved class is the one remaining flat
  lookup** — `Message` and `CreateFmt` both still bind pylib's, which is why
  `[%5d]` stayed unpadded and `.Message` stayed garbage.

That is a much smaller, precisely located job than anything this ticket has
described so far, and it is the LAST piece: find the property/method resolution
site, give it the class index that was already resolved instead of re-resolving
the name flat.

Final score of the hunt: four reasoned conclusions, all wrong; four probes, all
decisive — and the last one overturned the third. Every wrong turn came from
reading a downstream symptom (garbage bytes) as evidence about an upstream
mechanism (which parse site ran). The bytes were always telling the truth about
something else.

### Caveat on the entry above — "property lookup is flat" is NOT yet established

`FindUProp` takes a CLASS INDEX at every call site in `compiler/parser.inc`
(4023, 4260, 4270, 4593, 5646, 5712 — all `FindUProp(ci, ...)` or
`FindUProp(recName - REC_UCLASS_BASE, ...)`). So property resolution is already
class-scoped, and the previous entry's "still a flat lookup" is a HYPOTHESIS
from the symptom, not a fact from the code — exactly the move that has been
wrong four times in this hunt.

What is actually established: `.msg` (field) works, `.Message` (property) does
not, on the same object of the same resolved class. Both lookups are
class-scoped, so the difference lies elsewhere — the class index reaching the
property site, or the property's own accessor binding.

**Do not act on the previous entry's phrasing.** Probe it: print the class
index at the `FindUProp` call that resolves `se.Message`, and compare with 86.
That is the fifth probe, and on this ticket's record the probe will be right
and the reasoning will not.
