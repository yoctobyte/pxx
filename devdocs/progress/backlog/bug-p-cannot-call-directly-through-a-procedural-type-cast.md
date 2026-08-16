---
track: P
prio: 35
type: bug
blocked-by: []
summary: "`TFn(p)(args)` — calling straight through a procedural-type cast — is `unexpected token`, where FPC compiles and runs it. Assigning the cast to a variable first and calling that works, so the capability is present and only this spelling is refused. Hit twice while writing repros for the rtl-generics constant-initializer walls."
---

# Cannot call directly through a procedural-type cast

Found 2026-08-16 while clearing the record-constant walls in
[[feature-pascal-corpus-generics]]. Not folded into those fixes: it is a
different mechanism (expression-level call syntax, not constant initializers) and
they are green without it.

## Measured

```pascal
type TSelfFn = function(s: TB): LongInt;
var f: TSelfFn;

f := TSelfFn(V.QI); writeln(f(o));   { works — pxx and FPC agree }
writeln(TSelfFn(V.QI)(o));           { pxx: error: unexpected token }
```

| form | FPC 3.2.2 | pxx |
| --- | --- | --- |
| cast into a variable, then call | `5` | `5` |
| call directly through the cast | `5` | **`unexpected token`** |

Same for a plain `Pointer` const: `TPr(PP)()` is refused, `f := TPr(PP); f()` is
fine.

## Why it is a real gap rather than a style question

The capability is entirely present — the cast is legal, the resulting value is
callable, and one extra local makes it work. Only the direct spelling is refused,
so this is a parse-level hole and not a missing feature. It is also the natural
way to write a dispatch through a hand-built VMT, which is exactly the code that
led here: rtl-generics reaches its comparers this way.

Cost when it bites: the diagnostic is `unexpected token` with no indication that
a temporary would fix it, and it surfaces on the *call* line rather than at the
cast, so it reads as a problem with the argument list.

## Likely shape

After a type-cast expression is parsed, the postfix loop does not consider `(`
as a call on the result — the same postfix-continuation question as indexing or
`.field` on a call result. Worth checking whether `(` after a cast is handled for
any other receiver shape before adding a case; if the postfix loop is the single
place, this is one arm rather than a new path.

Related in kind (a construct reachable through two shapes, one wired and one
not): [[project_nilpy_lvalue_vs_selector_path_must_both_know]].

## Gate

Both rows above matching `fpc -O1 -Mobjfpc`, for a procedural cast of a record
field, a scalar const and a plain variable; `gate.sh quick`; self-host
fixedpoint.
