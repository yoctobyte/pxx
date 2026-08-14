---
track: A
prio: 75
type: feature
blocked-by: []
summary: "One Exception class in a shared builtin unit, re-exported by BOTH sysutils and pylib under their own names (`type Exception = exceptions.Exception`). Retires the catch bridge, the layout guard and the shared-name history in one move. Every mechanism verified 2026-08-14; the only member that does not merge cleanly is CreateFmt, and the hook that solves it is measured to work."
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
