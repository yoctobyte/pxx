---
track: A
prio: 70
type: bug
blocked-by: []
status: working
owner: agent-an
summary: "When a derived class declares a constructor that shadows an inherited one with a DIFFERENT signature, `TDer.Create(arg)` calls the BASE body while marshalling the argument for the DERIVED signature — a Variant record is passed where an AnsiString handle is expected, so the ctor receives garbage. Silent wrong value, no diagnostic, reproduces on master with no pylib involved. FPC runs the DERIVED ctor (measured)."
---

# A shadowing constructor: the call target and the argument marshalling disagree

Reproduces on `master`. Found while measuring
[[feature-a-one-exception-class-in-a-shared-unit]] — pylib's `Exception`
declares `Create(const m: Variant)` and inherits
`ExceptionBase.Create(const m: AnsiString)` — but **nothing about it is
specific to that design**, which is why it is filed here and not there.

*(This ticket replaces `bug-pascal-ansistring-literal-to-variant-param-passes-garbage`,
whose diagnosis was wrong: passing a string literal to a `Variant` parameter is
FINE. Measured — `const`/by-value parameters, plain procedures, plain class
methods, plain class constructors, string/char/int/float literals and variables:
all correct. The shadowing ctor is the whole of it.)*

## Reproduce — master, no pylib

```pascal
program v3;
type
  TBase = class
    msg: AnsiString;
    constructor Create(const m: AnsiString);
  end;
  TDer = class(TBase)
    constructor Create(const m: Variant);      { shadows, different signature }
  end;
constructor TBase.Create(const m: AnsiString);
begin msg := m; WriteLn('  BASE ctor got=[', m, ']'); end;
constructor TDer.Create(const m: Variant);
begin msg := m; WriteLn('  DER ctor got=[', m, ']'); end;
var d: TDer; s: AnsiString; vv: Variant;
begin
  d := TDer.Create('hello');   s := 'hello';
  d := TDer.Create(s);
  vv := 'hello';
  d := TDer.Create(vv);
end.
```

| call | pxx | FPC (oracle, `{$mode objfpc}`) |
| --- | --- | --- |
| `TDer.Create('hello')` | **`BASE ctor got=[  \`8�t]`** | `DER ctor got=[hello]` |
| `TDer.Create(s)` | **`BASE ctor got=[<~100 junk bytes>]`** | `DER ctor got=[hello]` |
| `TDer.Create(vv)` | `DER ctor got=[hello]` | `DER ctor got=[hello]` |

`TBase.Create('hello')` directly is correct, so the base ctor itself is fine.

## Two defects, and the second is the dangerous one

**1. The wrong ctor is chosen.** `FindUCtorOverloadArgs`
(`compiler/parser.inc:3610`) collects `create` candidates up the WHOLE parent
chain and then ranks them by argument type, so an exact `AnsiString` match on
the BASE beats the derived's `Variant`. Its own comment says *"Pascal keeps the
inherited-ctor lookup: FPC really does let `TSub.Create` resolve to the base's"*
— true only when the subclass declares no `Create`. **When it declares one
without `overload`, FPC HIDES the inherited set**, which the table above
measures. Note the NilPy arm three lines up (`if isNilPy and (nCand > 0) then
Break;`) already implements the hiding rule for Python and documents exactly
this failure — so the mechanism to fix it is already present, applied to one
frontend only.

**2. The argument is marshalled for the OTHER signature.** This is what turns a
debatable overload pick into garbage. The body that runs is `TBase.Create`
(`const m: AnsiString`), but the caller boxed the argument as a **Variant** —
the derived signature — so the ctor reads an AnsiString handle out of a Variant
record. Had both lookups agreed, the "wrong" pick would still have printed
`hello`.

**One question, two lookups that can disagree** — the same shape as the
qualified-class hunt in `feature-a-one-exception-class-in-a-shared-unit`, where
`ctorCi` was resolved correctly and then `idx` recomputed flat three lines
later. `devdocs/dev/normalise-dont-special-case.md`.

## Fix in this order — they are separable, and the order matters

1. **Make the marshalling use the ctor that was actually selected.** This alone
   converts a silent wrong VALUE into a defensible (if un-FPC-like) answer, and
   it is a correctness fix with no dialect question attached. Find where ctor
   arguments are boxed relative to `FindUCtorOverloadArgs`'s result; the two
   must come from one resolution.
2. **Then decide the hiding rule.** Making a derived `Create` hide the inherited
   set is FPC parity and is what the NilPy arm already does — but it is a
   dialect semantics change with a real blast radius (any class whose own ctor
   has a different arity from a base ctor that callers currently reach). If it
   is not obviously safe, it belongs behind `--strict-fpc`/`--strict-overload`
   with a `decide-*` ticket, per this repo's lax-by-default rule.

Do NOT do 2 before 1: fixing the pick would hide the marshalling bug rather than
remove it, and it would come back the moment any other path selects a different
overload from the one it marshals for.

## Sweep before closing

Same shape through the other construction routes, since a ctor is reachable
several ways: a NAMED shadowing ctor (`CreateFmt`), `TSomeClass(x).Create` via a
metaclass cast, `class of` dispatch (`BuildMetaclassNew`), and an `inherited
Create(..)` call from the derived body.

## Gate

The table above matches FPC on every row (or, if the hiding rule is deferred,
every row prints a correct message rather than garbage), the sweep list agrees
with `tools/fpc_diff_probe.sh`, `make compiler/pascal26` self-host converges,
`tools/gate.sh quick` green.
