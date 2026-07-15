---
summary: "passing @obj.Method directly as an argument to a named `of object` parameter type fails overload matching ('no overload matches') — assignment to the same type works"
type: bug
track: P
prio: 40
---

# @obj.Method as a call argument to a named method-pointer param: no overload match

- **Type:** bug (overload matching / parser). Compile error, not silent — pxx
  rejects a valid FPC program.
- **Track:** P (Pascal frontend overload matching of `@obj.Method` against an
  `of object` parameter type). The IR lowering for such a param already exists
  (IRLowerCallArg method-pointer-param path) — the arg just never reaches it
  because matching fails first.
- **Found:** 2026-07-15 while fixing
  [[bug-a-method-pointer-virtual-captures-static-address]] (the assignment form
  `fn := @obj.Method` works and is now VMT-correct; only the direct-argument
  form fails).

## Repro

```pascal
{$mode objfpc}{$H+}
type TB = class function M(a: longint): longint; virtual; end;
     TFn = function(a: longint): longint of object;
function TB.M(a: longint): longint; begin Result := a; end;
procedure Call(fn: TFn); begin Writeln(fn(5)); end;
var b: TB;
begin b := TB.Create; Call(@b.M); b.Free; end.
```

pxx: `error: no overload of Call matches these arguments`. FPC compiles and runs
(prints 5). The **assignment** `var fn: TFn; fn := @b.M; Call(fn);` works.

## Likely area

The overload matcher does not treat an `@obj.Method` (AN_METHODREF, typed
tyPointer in a value/arg context — see the parser note at the `@obj.Method`
build site) as assignment-compatible with a named `of object` record-type
parameter. The IR side already materialises the {Code,Data} pair for a
tyRecord method-pointer param (IRLowerCallArg), so this is purely a
match-time gap: accept an AN_METHODREF argument for a method-pointer-typed
(`of object`) parameter, mirroring the assignment-context acceptance.

## Acceptance

The repro compiles and prints 5; a `test/` regression covers `@obj.Method`
passed as an argument (both virtual and non-virtual); the event-handler idiom
(`Register(@Self.Handler)`) is exercised.

## Log
- 2026-07-15 — resolved, commit c74f63f6.
