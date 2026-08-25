---
track: A
prio: 5
type: compat
blocked-by: []
summary: "pxx compiles `var p: Pointer;` and `procedure P(...)` in the SAME scope and resolves both correctly — bare p is the variable, P(x) the routine. FPC rejects it ('overloaded identifier \"p\" isn't a function'), since Pascal is case-insensitive and those are one identifier. Assumed to be dialect laxness rather than a defect, on the precedent set for overload widening; --strict-fpc should reject it. Not filed as a bug: nothing resolves wrongly."
---

# `--strict-fpc` should reject a duplicate identifier in one scope

- **Type:** compat (FPC parity behind a flag) — **Track A** (duplicate-declaration
  detection is in the shared `parser.inc`/`symtab.inc`).
- Found 2026-08-14 when a differential probe compiled under pxx and would not
  compile under FPC — the *probe* was at fault, and that is what makes this
  worth recording: the two implementations disagree about whether the program is
  legal at all, so a sweep written against pxx can silently fail to be a
  differential test.

## Measured

```pascal
program dup;
var p: Pointer;
procedure P(const s: string);
begin WriteLn('proc called: ', s); end;
begin
  p := nil;
  P('hello');
  WriteLn('p is nil: ', p = nil);
end.
```

| | result |
| --- | --- |
| pxx | compiles; prints `proc called: hello` then `p is nil: TRUE` |
| FPC 3.2.2 | `dup.pas(3,12) Error: overloaded identifier "p" isn't a function` |

Pascal is case-insensitive, so `p` and `P` are the same identifier and FPC sees
a redeclaration.

## Why this is filed as compat and not as a bug

**Nothing resolves wrongly.** Checked the shape most likely to be ambiguous — a
variable and a *paramless function* under one name, where a bare mention could
go either way:

```pascal
var v: Integer;
function V: Integer; begin V := 42; end;
...
v := 7;
WriteLn(v);     { 7  — the variable }
WriteLn(V());   { 42 — the function }
```

pxx picks the variable for the bare name and the routine for a call, which is
coherent and is the same rule as
`frank2-paramless-name-semantics` (a bare paramless function name is its result
var; call it with `()`). So this is the dialect accepting more than the
reference, which the house rule treats as a feature —

> *"this widening is not a bug. BUT it affects `--strict-fpc` mode"* (user,
> 2026-08-14, on the sibling
> [[compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload]])

— and the parity work belongs behind the flag, exactly as there.

**Worth a second opinion on one point:** unlike overload widening, this
laxness lets a *typo* through — writing `p` where a distinct name was meant
declares a second entity instead of erroring. If that is judged to outweigh the
convenience, the call to make the DEFAULT reject it is a Track U `decide-*`, not
this ticket.

## Scope

- **Default dialect: unchanged**, pending the note above.
- **Under `--strict-fpc`:** a second declaration of a name already declared in
  the same scope is an error, whatever the case and whatever the two kinds are.
- Umbrella enrolment is a separate call, per the precedent in
  [[decide-may-uses-math-cost-the-heap-and-exception-runtime]] and
  `StrictOverload`'s standalone status — the corpora `--strict-fpc` is proven to
  compile must be re-checked, since real FPC code cannot contain this by
  construction but our OWN sources might.

## Sweep before closing

Other kind-pairs under one name in one scope: var/var, type/var, const/proc,
proc/proc without `overload`, a field and a method in one class, and a unit-level
name against an imported one (which is the transitive-`uses` question in
[[bug-pascal-uses-is-transitive]] and may already be decided differently).

## Gate

The repro errors under `--strict-fpc` and compiles without it; `make test` +
self-host fixedpoint; and the corpora `--strict-fpc` already compiles stay green
— **including this repo's own Pascal sources**, which is the risk the sweep note
above is about.
