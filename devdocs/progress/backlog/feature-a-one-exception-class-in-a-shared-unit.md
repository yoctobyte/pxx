---
track: A
prio: 75
type: feature
blocked-by: []
summary: "SUPERSEDED BY THE SIBLING DESIGN AT THE END — no hook needed. Also FIXES bug-nilpy-exception-repr-and-type-name-say-pyexception by construction. One Exception class in a shared builtin unit, re-exported by BOTH sysutils and pylib under their own names (`type Exception = exceptions.Exception`). Retires the catch bridge, the layout guard and the shared-name history in one move. Every mechanism verified 2026-08-14; the only member that does not merge cleanly is CreateFmt, and the hook that solves it is measured to work."
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
