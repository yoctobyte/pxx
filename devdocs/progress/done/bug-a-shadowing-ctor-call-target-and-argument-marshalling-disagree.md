---
track: A
prio: 70
type: bug
blocked-by: []
status: done
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

---

## Progress — STEP 1 DONE (agent-an, 2026-08-14). Step 2 deliberately not done.

### The two lookups, located

Found by `PXXDBG=a.ir:<proc>` on the repro, after `PXXDBG=a.ast` had shown the
AST holds a plain AnsiString literal — so the boxing is introduced during
lowering, not by the parser:

```
3: const_str ... tk=4        <- the literal, AnsiString
4: var_store ... tk=22       <- boxed into a VARIANT temp
6: arg  a=5 ... tk=4         <- passed as the Variant's address, tagged AnsiString
7: call a=-45 ...            <- ...to the BASE ctor
```

The two sites, both in `compiler/ir.inc`, both answering "which ctor is this?":

| site | lookup | policy |
| --- | --- | --- |
| argument coercion (`ctorArgCpi`, the `-tkGetMem` arg loop) | `FindUMeth(ci, 'create')` | name only, **derived first** → `TDer.Create(Variant)` |
| by-ref decision (`specialId = tkGetMem` arm) | `FindUMeth(ci, 'create')` | same |
| call target (`IRCtorProc`) | `FindUCtorOverloadArgs(ci, args)` | ranks the **whole chain** by arg type → `TBase.Create(AnsiString)` |

Two policies, one question. The argument was boxed for the derived signature and
handed to the base body, which read an AnsiString handle out of a Variant
record.

### Fix

Both marshalling sites now resolve with `FindUCtorOverloadArgs` — the same
lookup the call target uses — falling back to `FindUMeth` only when it declines,
so a class with no overload set behaves exactly as before.

Measured, the whole table:

| call | before | after | FPC |
| --- | --- | --- | --- |
| `TDer.Create('hello')` | garbage | `hello` | `hello` |
| `TDer.Create(s)` | garbage | `hello` | `hello` |
| `TDer.Create(v)` | `hello` | `hello` | `hello` |
| `TBase.Create('hello')` | `hello` | `hello` | `hello` |

**The silent wrong value is gone.** `tools/gate.sh quick` GREEN, self-host
converges.

### Regression test

`test/test_ctor_shadowing_signature.pas`, registered in the Makefile beside
`test_ctor_arrayofconst_overload_b298`. It asserts the **message**, never which
body produced it — deliberately, because which ctor wins is step 2 and this test
must not have to change when that is decided. What it pins is the invariant that
survives either answer: *the ctor that runs and the signature the argument was
marshalled for are the same one.* It includes the exact-Variant argument (so a
"fix" that stopped boxing everything is caught) and the base-ctor control (so a
fix that moved the bug rather than removing it is caught).

### Step 2 is still open, and is a DIALECT decision

pxx now runs `TBase.Create` for a string literal — the exact type match, ranked
across the chain. FPC runs `TDer.Create`, because a descendant's method **hides**
the inherited set unless declared `overload`. Both print `hello` now, so the
divergence is a surprise rather than a corruption.

Deciding it is not free: making a derived `Create` hide the inherited set changes
what compiles for any class whose own ctor has a different arity from a base ctor
its callers currently reach. The mechanism already exists —
`FindUCtorOverloadArgs` has an `isNilPy` arm that breaks on the first class with
candidates, added because this same bug constructed a bare `tk.Frame` — so the
work is small and the RISK is what needs a human. Per this repo's lax-by-default
rule that is a `--strict-fpc` / `--strict-overload` question.

**Not filed as a separate ticket** — it is the second half of this one, and
splitting it would lose the measured table above. Re-open here when the
strictness umbrella is next touched (`meta-dialect-extensions-and-fpc-strict`).

### Sweep — DONE, and it is CLEAN

All five other construction routes measured on the same shadowed pair:

| route | result |
| --- | --- |
| named shadowing ctor (`TDer.Make('b')`) | correct |
| `class of` dispatch, `Create` | correct |
| `class of` dispatch, named ctor | correct |
| inline metaclass cast `TDerClass(o.ClassType).Create` | correct |
| `inherited Create(m)` from the derived body | correct |

**Controlled against the PRE-FIX compiler, not against a text edit** — the same
source built with `stable_linux_amd64/default/pinned` (v300, which predates this
fix) shows route 1 garbled and these five already correct. So the sweep is a
real instrument: it does show the bug where the bug is, and it found no second
instance. Plain `Create` was the only route whose two lookups disagreed.

All six are now in `test/test_ctor_shadowing_signature.pas`. The test FAILS
under pinned v300 (2 failures, the literal and the variable) and passes at HEAD,
which is what makes it a regression test rather than a snapshot.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
