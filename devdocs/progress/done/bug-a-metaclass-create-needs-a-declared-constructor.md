---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`classRef.Create` failed to compile — with a diagnostic about pointers, not about constructors — whenever the class hierarchy declared no constructor of its own and `Create` therefore meant the implicit TObject.Create. The static `TFoo.Create` spelling had accepted that since forever, so the factory idiom worked or not depending on an unrelated property of the target class. Both metaclass spellings fixed; found by an OOP differential against FPC 3.2.2."
---

# `classRef.Create` demanded a declared constructor

- **Type:** bug (compile-time refusal of valid code, with a misleading
  diagnostic) — Track A (`pasparser_lval.inc`, `pasparser_expr.inc`, `ir.inc`).
- **Status:** done
- **Opened:** 2026-08-21, from a 27-program OOP differential against FPC 3.2.2.
- **Closed:** 2026-08-21.

## Symptom

```pascal
type
  TBase = class
    function Name: AnsiString; virtual;
  end;
  TBaseClass = class of TBase;
  TDer = class(TBase)
    function Name: AnsiString; override;
  end;
var cr: TBaseClass; o: TBase;
begin
  cr := TDer;
  o := cr.Create;          { FPC: fine. pxx: }
end.
```

```
pascal26:16: error: "Create": a pointer has no members (dereference it with ^,
  or the pointee type is unknown here)
```

Add `constructor Create; virtual;` to `TBase` (and an `override` on `TDer`) and
the identical program compiles and runs correctly. So the factory idiom — the
entire reason `class of` exists — worked or did not work depending on whether
the target class happened to declare a constructor, which is a property with no
bearing on the call.

The diagnostic made it worse. It talks about *pointers* and suggests `^`,
because control had fallen all the way through the metaclass branch into the
generic "member on a pointer" error at the bottom of the selector loop. Nothing
in it points at constructors, so the reader's first guess is a type problem.

## Root cause

Two of the three spellings of "construct through a class value" resolve the
constructor by name lookup, and the third does not:

| spelling | resolves via | implicit `TObject.Create`? |
| --- | --- | --- |
| `TFoo.Create` (static) | a literal `Create` fast path in `ParseFactor` | **yes**, always |
| `cref.Create` (metaclass var) | `FindUMeth` in `ParseMetaclassMemberTail` | no — `-1` → fall through |
| `TFooClass(x).Create` (inline cast) | `FindUMeth` + `UMthIsCtor` in `ParseFactor` | no — gate fails |

`FindUMeth` answers `-1` for a class that declares no constructor anywhere up
its chain, because the implicit root constructor is not a `UMeth` — it does not
exist as a declaration anywhere. The static path never asks: it matches the
*name* `Create` and builds the construction directly. The other two ask, get
`-1`, and give up.

This is the textbook double case from
`devdocs/dev/normalise-dont-special-case.md`: one construct reachable through
several shapes, generality added to one shape only, and the shapes that were not
touched are the ones that stayed broken. Here it was two of three — and finding
the first (`cref.Create`) is what said to go looking for the second
(`TFooClass(x).Create`), which failed with a *different* message
("no such member on this record/class") and would otherwise have been filed
weeks later as an unrelated bug.

## Fix

`mmi = -1` becomes a legal argument to `BuildMetaclassNew`, meaning "the
implicit root constructor":

- `BuildMetaclassNew` sets `mpi = -1` and vmt slot `-1`, accepts the empty
  parens FPC accepts, and **refuses arguments** rather than dropping them
  silently (`this class declares no constructor, so Create takes no arguments`
  — FPC says `Wrong number of parameters specified for call to "Create"`).
- `ParseMetaclassMemberTail` falls back to it when `FindUMeth` misses and the
  name is `Create`.
- The inline-cast arm in `ParseFactor` gets the same fallback in its gate.
- IR lowering: `cpi < 0` returns the instance right after the allocate-and-stamp
  step. There is no constructor body to call — FPC's `TObject.Create` is empty —
  so allocating and stamping the VMT *is* the whole construction.

No new AST node, no new IR op, no backend change.

## Verification

`test/test_metaclass_implicit_create.pas`, wired into `test-core`, **byte-identical
to fpc 3.2.2** across eight rows: implicit ctor with empty parens, without
parens, two levels down the hierarchy, on the base class itself, through an
inline metaclass cast, plus the declared-virtual-ctor arm in both directions
(so a regression either way shows) and the loop-over-class-refs factory shape.

Checked separately and matching FPC: an instance built this way is
zero-initialised, and arguments to the implicit `Create` are rejected at compile
time.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Not done

`pyparser.inc` carries its own copies of both call sites (Track N owns that
file, and N work is deferred). NilPy's class model does not reach the implicit
root ctor the same way, so nothing is known to be broken there — but if a NilPy
metaclass construction ever reports "a pointer has no members", this is the
shape to check first.
