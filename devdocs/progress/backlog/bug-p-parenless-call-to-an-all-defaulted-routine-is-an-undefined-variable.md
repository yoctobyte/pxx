---
track: P
prio: 50
type: bug
summary: "`P;` on a free routine whose parameters are ALL defaulted fails with 'undefined variable (P)'. FPC accepts it, `P()` works, and the paren-less form already works for METHODS (`b.G`) and for routines with no parameters at all — so it is the free-routine path alone that never tries the defaults fill"
---

# `P;` fails when every parameter is defaulted

- **Type:** bug (Pascal frontend — call parsing)
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N, writing repros for
  [[bug-p-float-literal-default-in-a-parameter-list-fails-to-parse]] — the
  natural way to write the call is `P;` and it did not compile.

## Repro

```pascal
program n;
procedure P(k: Integer = 3); begin writeln('k=', k); end;
begin P; end.
```

```
pascal26:3: error: undefined variable (P)
```

## What narrows it

| shape | result |
| --- | --- |
| `procedure P; ... P;` (no parameters) | ok |
| `procedure P(k: Integer = 3); ... P;` | **error: undefined variable (P)** |
| `procedure P(k: Integer = 3); ... P();` | ok, `k=3` |
| `b.G` where `G(x: Integer = 3)` is a method | ok (covered by `test_default_params_methods`) |

So: the paren-less form works with no parameters, and works for methods with
defaulted ones. Only the **free-routine** paren-less path fails, and only when
parameters exist to be filled.

The diagnostic is the misleading part — "undefined variable" says the *name*
was not found, when the name resolved fine and the *arity* is what did not.
That wording will send the next reader looking at scope and unit order.

## Likely cause (unverified)

A bare identifier in statement position is resolved as a variable/expression
first; the fallback to "call with zero arguments" evidently only fires when the
routine's `ParamCount` is 0, so it never reaches the trailing-defaults fill
(`CanFillDefaultsFrom` / `TryFillTrailingDefaults` in `compiler/parser.inc`).
The method path reaches the fill because it goes through the member-access
route instead. **Measure before writing this into a fix** — the analogous claim
about the ctor path in a sibling ticket was right for a different reason than
the ticket first stated.

## Gate

The repro compiling and printing `k=3`; a `P;` case added to
`test/test_default_params_methods.pas` (the home for defaulted-parameter
behaviour); `tools/gate.sh quick`.

## Note

Low prio deliberately: it is a clean compile error with an obvious workaround
(`P()`), so nothing silently misbehaves — unlike the two corruption bugs found
in the same sweep. The bad *wording* is the part worth fixing even if the
paren-less form is judged out of scope; if it is judged out of scope, that is a
Track U call — file `decide-` rather than closing it silently.
