---
track: P
prio: 62
type: bug
blocked-by: []
summary: "A parameterless function used as an ARGUMENT to a method call fails to resolve — `error: undefined variable (zero)` — while the identical argument to a free function compiles. Any argument position. Found writing lib/rtl/mimic_urllib_request.pas, where `headers.get(name, pynone)` would not compile but `HeaderFirst(raw, name, pynone)` did."
status: done
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

## Log
- 2026-08-26 — resolved, commit d6785805c.

# Resolved 2026-08-26

The ticket's framing — "works for a free function, fails for a method" — is
true but is not the boundary. Varying the shape narrowed it much further:

| shape | before |
| --- | --- |
| FREE function, `const Variant` param, bare `zero` | compiles |
| method, `const Variant`, bare `zero` | **`undefined variable (zero)`** |
| method, by-VALUE `Variant`, bare `zero` | compiles |
| method, `const AnsiString`, bare `zstr` | compiles |
| method, `const Variant`, explicit `zero()` | compiles |
| method, `var Variant`, bare `zero` | refused (correctly) |

So it is not method-vs-free and not by-ref-vs-by-value: it is **method +
`const Variant` + a BARE name**, one cell.

## Cause

`ByRefArgStartsExpression` (`compiler/pasparser_call.inc`) decides whether a
by-ref argument is an expression or a bare variable lvalue. Its last line
admits an unresolvable name only when a `(` follows — that is the type-cast
lvalue case (`PChar(s)^`). A bare `zero` names no *symbol*, so it fell to the
bare-lvalue arm, reached `ParseLValueAST` with `FindSym = -1`, and was reported
as an undefined variable. `PXXDBG=a.qual` showed it exactly:
`MEMBER field=z flat=-1` — the parser was looking `zero` up as a class member.

A name that resolves to no symbol but to a parameterless (or all-defaulted)
FUNCTION is now an expression. A `const Variant` parameter is by-ref internally
but is never a var-binding target, so a call's result is a legal argument.

## The gate on that clause is load-bearing — this was measured, not assumed

The clause was first written **ungated**, on the reasoning that "it is a call,
so it is an expression" holds for any by-ref parameter and would also let a
genuine `var` parameter produce the *right* refusal instead of the wrong one.

That is wrong, and the negative test caught it: the method by-ref path has **no
validator that rejects a non-lvalue argument** — it relies on this predicate
answering False to force the bare-lvalue parse. Ungated, `o.f(zero)` with
`var b: Variant` COMPILED, binding a call result to a var parameter where fpc
says "Can't take the address of constant expressions". Silently accepting is
worse than a badly worded refusal, so the clause stays inside the existing
`PyExprMode or constVariantParam` gate.

Corroborating measurement: `o.f(a + b2)` with a `var` param answers `wrong
number of parameters` — the parse stopped at the `+`. That is the same missing
validator seen from another angle.

## Known wart, left open deliberately

Method + `var Variant` + a bare paramless function still says
`undefined variable (zero)` rather than naming the real problem. It is wrong
WORDING on a CORRECT refusal, it predates this fix, and fixing it properly
means giving the method by-ref path the non-lvalue validator it lacks — which
is a real change to a gated path and is not what this ticket is about.
`test/test_paramless_fn_as_var_arg_refused.pas` asserts only that the program
does not compile, so the wart is documented without being frozen.

## Verified against fpc 3.2.2, byte-identical

`test/test_paramless_fn_as_const_variant_arg.pas` covers the free call, the
method call, an OVERLOADED method (which takes the arity-probe path), a static
class method, a record method, an all-defaulted function, the explicit-parens
spelling, by-value Variant and `const AnsiString`. All ten rows match fpc.
The original two-file unit repro from this ticket now prints `7 / 7 / 7`, the
same as fpc.
