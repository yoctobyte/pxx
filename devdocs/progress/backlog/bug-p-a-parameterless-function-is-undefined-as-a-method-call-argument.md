---
track: P
prio: 35
type: bug
blocked-by: []
summary: "A parameterless function used as an ARGUMENT to a method call fails to resolve — `error: undefined variable (zero)` — while the identical argument to a free function compiles. Any argument position. Found writing lib/rtl/mimic_urllib_request.pas, where `headers.get(name, pynone)` would not compile but `HeaderFirst(raw, name, pynone)` did."
---

# A parameterless function is `undefined variable` as a METHOD-call argument

- **Type:** bug (Pascal frontend) — **Track P**.
- **Filed:** 2026-08-18 by frank3-b, while writing
  `lib/rtl/mimic_urllib_request.pas`
  ([[feature-b-mimic-urllib-request-over-the-rtl-http-stack]]).
- **Shared-file catch:** the fix is almost certainly in the argument-parsing
  path of the SHARED `compiler/parser.inc`, which Track P and Track A both
  touch. Whoever takes it obeys A's gate and the no-concurrent-edit rule.

## The bug

Calling a parameterless function to produce an argument works when the callee
is a free function and fails when the callee is a **method**. The name is
reported as an undefined *variable*, so the diagnostic points at the argument
rather than at the call being resolved.

## Repro — self-contained, two files

`mrep.pas`:

```pascal
unit mrep;
interface
type
  K = class
  public
    constructor Create;
    function one(const b: Variant): Variant;
    function two(const a: AnsiString; const b: Variant): Variant;
  end;
function zero: Variant;
function freetwo(const a: AnsiString; const b: Variant): Variant;
procedure drive;
implementation
constructor K.Create; begin end;
function K.one(const b: Variant): Variant; begin one := b; end;
function K.two(const a: AnsiString; const b: Variant): Variant; begin two := b; end;
function zero: Variant; begin zero := 7; end;
function freetwo(const a: AnsiString; const b: Variant): Variant; begin freetwo := b; end;
procedure drive;
var k: K; v: Variant;
begin
  k := K.Create;
  v := freetwo('a', zero);   { FREE function argument — COMPILES }
  v := k.two('a', zero);     { METHOD, 2nd argument — error }
  v := k.one(zero);          { METHOD, sole argument — error }
  writeln(v);
end;
end.
```

`mrep_main.pas`: `program mrep_main; uses mrep; begin drive; end.`

```
$ pinned -Fu<dir> mrep_main.pas out
pascal26:22: error: undefined variable (zero)
  near:  two  a  zero >>>   writeln
```

## What was measured

Against `stable_linux_amd64/default/pinned` at HEAD `df15ae3fe`.

- **Free function callee: fine.** `freetwo('a', zero)` compiles and runs.
- **Method callee: fails.** Both `k.one(zero)` and `k.two('a', zero)` fail, so
  it is **not** an argument-position or arity effect.
- **Not an overload effect.** First seen on an overloaded pair, but it
  reproduces with a single non-overloaded method — the overload was a red
  herring and is called out here so nobody re-derives it.
- **Not specific to `pynone`.** First seen as `headers.get(name, pynone)` in
  the RTL; a locally declared `function zero: Variant` fails identically, so it
  is any parameterless function, not a pylib visibility problem.
- The same free-function call in the same scope, on the line above, compiles —
  so the name IS in scope. Only the method-call argument path fails to find it.

## Why it is p35 rather than higher

There is a natural spelling that avoids it (bind to a local first, or route the
call through a free function), it is a hard compile error rather than a wrong
value, and the diagnostic — while pointing at the wrong thing — does name the
identifier. But it is a plain scope bug in the most ordinary shape there is, and
it silently shapes library code: the RTL's `mimic_urllib_request.pas` reads the
way it does partly because of this.

## Note for whoever fixes it

`lib/rtl/mimic_urllib_request.pas` was written around this and says so where it
matters. Its `HeaderFirst` free function is **not** a workaround to unwind — it
is one lookup shared by three CPython spellings and should stay — but the
comment there that explains the constraint can come out once this is fixed.
