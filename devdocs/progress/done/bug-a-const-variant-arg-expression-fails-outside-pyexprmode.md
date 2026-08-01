---
track: A
prio: 30
type: bug
blocked-by: []
---

# `obj.method(a + b)` to a `const Variant` param fails to parse OUTSIDE NilPy

`bug-nilpy-expression-arg-to-a-const-param` (already fixed, see the comment on
`ByRefArgStartsExpression` in `compiler/parser.inc:3552`) fixed `xs.append(a +
b)` for NilPy source — a `const Variant` parameter is by-ref internally (boxed
at `IRLowerCallArg`), so the by-ref argument parser tried to bind the argument
as a bare lvalue and choked on the operator after the first identifier. The fix
is gated `if PyExprMode then ... end;` inside `ByRefArgStartsExpression`.

That gate means the identical shape still fails in **plain Pascal source**
(`PyExprMode = False`), including a Pascal RTL unit's OWN body — found writing
`pylib.pas` itself:

```pascal
function pyenumerate2(a: TPyList; start: Integer): TPyList;
var r, pair: TPyList; i: Integer; pv: Variant;
begin
  ...
  pair.append(start + i);   { TPyList.append(const v: Variant) }
  ...
```

fails with:
```
pascal26:NNNN: error: unexpected token
  near:  pair  append  start >>>  i
```
(`Expected: ), but got: tkPlus` — the same shape as the original NilPy bug, one
level down: worked around locally by assigning `start + i` to a local variable
first before the `.append()` call, but the underlying parser gap is general.

## Root cause

`ByRefArgStartsExpression` (`compiler/parser.inc:3552`) only runs its
lvalue-chain-skip-then-check-what-follows logic (the actual fix) when
`PyExprMode` is true. Outside that mode it falls through to the old rule:
`Result := (FindSym(CurTok.SVal) < 0) and ... tkLParen` — true only for an
unresolved-identifier-followed-by-`(` (a cast-lvalue like `PChar(s)^`), false
for a plain declared variable, so `start` (a real local) reads as "starts a
bare lvalue" and the by-ref arg parser stops after consuming just `start`.

## Fix direction

The PyExprMode gate exists to protect genuine Pascal `var`/`out` parameter
binding (which really does need a true lvalue, in both Pascal and NilPy). But
a `const Variant` parameter is NEVER a genuine var-binding target — the
existing by-ref-argument-validator two call sites up
(`(Params[i].TypeKind = tyVariant) and ProcParamIsConst[...]`) already treats
it as accepting a non-lvalue temporary. So `ByRefArgStartsExpression` should
run its lvalue-chain-skip-and-check logic unconditionally whenever the current
parameter is `const Variant`, regardless of `PyExprMode` — only genuine
var/out/array by-ref params should still require the gate.

This needs threading the callee's "is this a const Variant param" fact into
`ByRefArgStartsExpression` (it currently takes no arguments) at each of its ~8
call sites in `compiler/parser.inc` (plain calls, method calls, interface
calls — grep `ByRefArgStartsExpression`), each of which already has `mpi`/
`mslot` or `procIdx`/`i` in scope to compute
`(Procs[..].Params[..].TypeKind = tyVariant) and ProcParamIsConst[...]`.
Scoped as its own ticket since it touches the shared Pascal/NilPy binop/call
parsing in `parser.inc` at several sites and needs the self-host gate;
deliberately not attempted inline while sweeping for the set/dict-operator fix
(bug-nilpy-set-and-dict-operators-do-raw-pointer-arithmetic).

## Log
- 2026-08-01 — resolved, commit 05b8ce4c5.
