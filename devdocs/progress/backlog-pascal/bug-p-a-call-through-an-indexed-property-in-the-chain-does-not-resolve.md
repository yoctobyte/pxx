---
slug: bug-p-a-call-through-an-indexed-property-in-the-chain-does-not-resolve
title: "Calling a method pointer reached through an INDEXED PROPERTY does not resolve"
track: P
prio: 45
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-06 at 67b07bc9e, compiler 3bc524a975bd. THE SIBLING ARM OF [[bug-p-at-over-a-class-base-consumes-only-one-selector]], WHICH LANDED HOURS EARLIER AND CLOSED ONLY THE `@` HALF. That fix made `@o.Items[0].Ev` parse; CALLING the same thing still does not. `o.Items[0].Fn(1)` is refused where `o.Ev(1)` and `o.R.Ev(1)` both compile, so the failing ingredient is the INDEXED PROPERTY in the chain and NOT the chain depth -- a record field chains fine. fpc 3.2.2 -Mdelphi compiles and runs it (prints `yes`). ONE CAUSE, TWO FACES, and neither names the real subject: in statement position it says `o is not a procedure or function, so it cannot be called` -- blaming the BASE identifier for a callee four selectors away -- and in expression position `expected 'then' before '('`. FOUND BY RE-RUNNING THE CORPUS TARGET AFTER THE SIBLING LANDED: uPSCompiler's wall moved 5031 -> 5033, i.e. TWO LINES, from `@Func.Attributes.Items[i].AType.OnApplyAttributeToProc` to the very next statement calling that same field, `Func.Attributes.Items[i].AType.OnApplyAttributeToProc(Self, Func, ...)`. That two-line move is the finding: the `@` arm and the call arm are one construct read two ways, and closing one without grepping for the other bought two lines of corpus. Reduced repro is 12 lines and needs no library."
---

# Calling a method pointer reached through an indexed property

- **Type:** bug (Pascal frontend — call resolution through a designator chain)
- **Track:** P
- **Found:** 2026-09-06, re-running [[feature-embed-pascal-script]] after
  [[bug-p-at-over-a-class-base-consumes-only-one-selector]] landed

## The boundary

`-Mdelphi`, at `67b07bc9e` / compiler `3bc524a975bd`:

| shape | pxx | fpc |
| --- | --- | --- |
| `o.Ev(1)` — field, one dot | compiles | compiles |
| `o.R.Ev(1)` — through a **record** field | compiles | compiles |
| **`o.Items[0].Fn(1)` — through an indexed property** | **refused** | compiles, prints `yes` |

```pascal
type TFn = function(x: Integer): Boolean of object;
     TInner = record Fn: TFn; end;
     TR = class private FI: TInner; function GetI(i: Longint): TInner;
          public property Items[i: Longint]: TInner read GetI; default;
          function F(x: Integer): Boolean; end;
...
if not o.Items[0].Fn(1) then writeln('no') else writeln('yes');
```

## Two diagnostics, one cause, and neither names the subject

| context | reported |
| --- | --- |
| statement — `o.Items[0].Ev(1);` | `o is not a procedure or function, so it cannot be called` |
| expression — `if not o.Items[0].Fn(1) then` | `expected 'then' before '('` |

The first is the actively misleading one: **it blames `o`**, the base identifier,
for a callee four selectors further along. Anyone reading it will go looking for
a `procedure o`.

## Why this is filed as a sibling and not as a reopen

`bug-p-at-over-a-class-base-consumes-only-one-selector` is correctly `done` —
its own four rows pass, verified by running them against this binary rather than
by reading the folder. It fixed **taking the address**. Taking the address and
**calling** are the same construct read two ways, and only one arm moved.

`devdocs/dev/normalise-dont-special-case.md` says it exactly: *"Fixed one arm of
a double case? Grep for the sibling before closing."* The evidence here is
unusually cheap to state — **the corpus wall moved two lines**, 5031 to 5033,
from `@Func.Attributes.Items[i].AType.OnApplyAttributeToProc` to the statement
that calls that same field.

## Done when

The three rows above compile, `o.Ev(1)` and `o.R.Ev(1)` still work, the
statement-position diagnostic names the callee rather than the base, and
uPSCompiler gets past 5033.
