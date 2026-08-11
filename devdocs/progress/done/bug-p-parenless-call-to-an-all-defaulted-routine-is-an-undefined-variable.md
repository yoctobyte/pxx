---
track: P
prio: 50
type: bug
summary: "`P;` on a free routine whose parameters are ALL defaulted fails with 'undefined variable (P)'. FPC accepts it, `P()` works, and the paren-less form already works for METHODS (`b.G`) and for routines with no parameters at all — so it is the free-routine path alone that never tries the defaults fill"
status: done
owner: claude-AN
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

## Resolution (2026-08-11)

### The ticket's "likely cause (unverified)" was right — confirmed, not assumed

`parser.inc:21412`, the bare paren-less call STATEMENT:

```pascal
else if (si < 0) and (procIdx >= 0) and (Procs[procIdx].ParamCount = 0) then
```

An all-defaulted routine has `ParamCount > 0`, so the arm never fired, the name
fell through to the assignment path, and `ParseLValue` reported *"undefined
variable (P)"* — the name HAD resolved; the arity had not, which is exactly why
the wording sends readers to look at scope.

The arm now also accepts a routine whose parameter 0 carries a default, and
calls the existing `FillDefaultArgs(procIdx, 0, ...)`. Testing parameter 0 alone
is sufficient because Pascal requires defaults to be **trailing**.

### The sibling — found by testing for it, not by the ticket

The ticket reports statement position. Probing the neighbouring shape after the
fix showed `a := F` still failing identically: `ParseFactorCore`'s
expression-position arm (`parser.inc:14407`) had **the same `ParamCount = 0`
test**. Both arms are fixed; fixing only the reported one would have left the
half a reader hits five minutes later.

Argument position (`Check('x', F, 6)`) is a THIRD site and deliberately left
alone: bare `F` there could equally be a procedural-type reference, so it is a
question to answer rather than a gate to widen. The test notes this.

### The widening's own hazard, checked before landing

Making a bare name callable puts it in reach of `F := expr` inside `F` — the
self-name Result assignment, which must NOT become a recursive call. It does
not: the existing `si < 0` / `idx < 0` guard sees the Result binding first.
Asserted directly (`PlSelfRes` in the test), because "it happens to still work"
is not something to leave unpinned.

### One trap worth recording

The first draft named those helpers `FR` / `FRes`, and
`parenless-expr-selfresult` failed with a garbage value — which read as a
codegen bug in the new path. It was not: the test file already has a local
`fr: TFRec`, PXX matches case-insensitively, so `FR` resolved to the **record
variable** and the check read uninitialised memory. The shadowing guard was
working exactly as designed. Renamed to `PlSelfRes` / `PlResVar`, with the
reason in the test so it is not re-introduced.

### Verified

The ticket's repro prints `k=3`. `test/test_default_params_methods.pas` grows
22 → 31 checks: paren-less with one default, two defaults, partial explicit, a
managed-string default, a float default, and the three expression-position
cases. **It fails on `stable_linux_amd64/default/pinned` with the ticket's own
diagnostic** ("undefined variable (PL1)"), so it is a regression test rather
than a passing example. Gate: `tools/gate.sh quick` GREEN.

## Log
- 2026-08-11 — resolved, commit ac45498bd.
