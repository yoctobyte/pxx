---
slug: bug-p-a-procvar-named-like-a-routine-calls-nil
track: P
prio: 50
type: bug
status: backlog
owner: ""
created: 2026-09-28
found-by: frankD (writing test_param_cap_at_the_limit.pas; FPC refused the file and pxx segfaulted at run time)
tags: [pascal, scope, procvar, silently-wrong]
blocked-by: []
summary: "A procedural variable whose name differs from a routine's only in case (`var f: TF` beside `function F`) compiles, and `f := @F; f(21)` then SIGSEGVs at run time: the call goes through nil. FPC 3.2.2 refuses the program (Duplicate identifier \"F\"). The rejected ticket compat-pascal-strict-fpc-should-reject-a-duplicate-identifier-in-one-scope accepted this laxness on the premise that pxx 'resolves both correctly'. For a var p / procedure P pair that holds; for a procvar and a routine it does not."
---

# A procedural variable named like a routine calls nil

```pascal
program dup;
type TF = function(x: Integer): Integer;
function F(x: Integer): Integer;
begin F := x * 2; end;
var f: TF;
begin
  f := @F;
  WriteLn(f(21));      { pxx: SIGSEGV (rc 139). FPC: refuses to compile. }
end.
```

Measured 2026-09-28 on the tip after 96be557c0e (fixedpoint 50df7d498542).

FPC 3.2.2 refuses it with `Error: Duplicate identifier "F"`, and then
`Incompatible types: got "Pointer" expected "<procedure variable type of
...>"`. The second error hints at what pxx does silently: `@F` resolves to
something other than the routine, the procvar stays nil or wrong, and the
call faults.

## Why this is not the rejected ticket

`compat-pascal-strict-fpc-should-reject-a-duplicate-identifier-in-one-scope`
(rejected) covered `var p: Pointer` beside `procedure P(...)`, where pxx
resolves bare `p` to the variable and `P(x)` to the routine, both correctly.
It rejected only the refusal, as dialect laxness. Here the two readings
collide in one expression, `@F` with `f` in scope, and the result is a crash
rather than a lax acceptance. The rejection's premise does not hold for this
shape.

## Next step

Measure what `@F` evaluates to when a same-named (case-insensitively) procvar
is in scope: the variable's address, or nil. Then choose between refusing the
declaration, as FPC does, and resolving `@F` to the routine.
