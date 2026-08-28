---
track: P
prio: 55
type: bug
blocked-by: []
summary: "In {$MODE DELPHI}, specializing a generic inside a method body fails when that generic is declared LATER in the same type section: `Result := TDeriv<T>.Create` compiles when TDeriv precedes TBase and reports `undefined variable (specialize)` when it follows. FPC accepts both. Reduced to a 14-line repro whose only difference is the order of two declarations. This is rung 3's wall past the RTTI blocker (generics.defaults.pas:3250)."
---

# A generic specialized before its declaration is unresolvable in DELPHI mode

Found 2026-08-28 by frankB (Track P) driving `feature-pascal-corpus-generics`
rung 3, after the typinfo/PTypeData blocker cleared and the wall moved from
**2082 to 3250**.

## The repro — one line of difference, and an oracle on both sides

```pascal
program y_after;
{$MODE DELPHI}{$H+}
type
  TBase<T> = class
    class function Ordinal: TObject;
  end;
  TDeriv<T> = class            { declared AFTER the class that uses it }
  end;
class function TBase<T>.Ordinal: TObject;
begin
  Result := TDeriv<T>.Create;
end;
type TInst = TBase<UnicodeString>;
begin WriteLn(Assigned(TInst.Ordinal)); end.
```

```
pascal26:11: error: undefined variable (specialize)
  near: TObject  begin Result  specialize >>> TDeriv  UnicodeString
pascal26:11: error: undefined variable (TDeriv)
```

Move the `TDeriv<T>` declaration **above** `TBase<T>` — changing nothing else —
and pxx compiles and runs it. **fpc 3.2.2 accepts both orderings** and prints
`TRUE` for each, so there is a live oracle on both arms, not just on the failing
one.

## What is NOT the trigger

Each of these was varied independently and none of them matters; recorded so the
next reader does not re-walk the ladder:

| variation | result |
| --- | --- |
| `{$mode objfpc}` with explicit `generic` / `specialize` | **compiles** — the defect is DELPHI-mode only |
| specializing a DESCENDANT vs an unrelated SIBLING | fails either way |
| one type parameter vs two | fails either way |
| generic name overloaded by arity (`TBox<T,F>` and `TBox<T>`) | compiles — not this |
| `class var` present or absent | irrelevant on its own |
| `class function` vs plain method | irrelevant on its own |
| the specialization inside `if ... then` vs a direct `Result :=` | irrelevant on its own |

The only thing that moves the verdict is **which of the two types is written
first**. Every "combination" that looked load-bearing at first was an artifact
of my repros happening to also reorder the declarations.

## Two more measurements that narrow it to instantiation time

| variant of the failing program | result |
| --- | --- |
| nothing instantiates `TBase` (drop `TInst`, empty main) | **compiles** |
| the body writes `TDeriv<UnicodeString>` — a CONCRETE argument — instead of `TDeriv<T>` | **compiles** |

So the defect needs all three of: DELPHI mode, the argument being the enclosing
template's own PARAMETER, and the enclosing template actually being
instantiated. Neither the declaration nor the parameterised body is enough on
its own — the failure is at instantiation time, on a token group that does not
exist in the original source.

That is the useful part for whoever fixes it: with a concrete argument the group
`TDeriv<UnicodeString>` is present in the token stream from the start and is
rewritten normally. With `TDeriv<T>` the concrete group only comes into
existence when `TBase` is instantiated and `T` is substituted — and by then the
rewriting for `TDeriv` has already run.

## Why it is DELPHI-mode only, and where to look

In `{$mode objfpc}` the programmer writes `specialize` and the token is in the
source. In DELPHI mode there is no such keyword — pxx **inserts** it while
normalising `X<T>`, and the `near:` window shows the inserted token:
`begin Result specialize >>> TDeriv UnicodeString`. The failing arm therefore has
the parser meeting its own inserted `specialize` in expression position and
resolving it as an identifier, which is why the diagnostic says
**`undefined variable (specialize)`** — a message that names a keyword as a
variable, which is itself the tell.

The two arms differ only in whether the generic's symbol exists at the moment
that normalisation runs, so the likely cause is that the DELPHI `<...>` rewrite
is driven off a lookup that happens during a single forward pass rather than
after the type section is complete.

**Do not fix it by making the resolver tolerate the token.** This is the
double-case shape from `devdocs/dev/normalise-dont-special-case.md`: the same
construct is reachable through declared-before and declared-after, one path
works, and the second path is the one that stays broken. The
declared-before arm is the normal form; the fix is to make declared-after
reach it, not to grow a second arm.

## Gate

`make compiler/pascal26` (self-host fixedpoint) plus both repro arms compiling
and printing `TRUE`, plus the corpus wall at `generics.defaults.pas:3250`
moving. Add both orderings as an fpc-derived regression pair in `test-core` —
**both arms**, since the passing one is what stops a fix from being written as a
special case.

## Scope

Track P (Pascal frontend, generic specialization in DELPHI mode). If the fix
turns out to need a change below the frontend — IR ops, backends, ABI — that is
a Track A ticket to file, not to edit under P.


## Localisation — measured vs inferred, kept apart

**Measured:** every `specialize` handler is in `compiler/pasparser_*.inc`
(`_generic`, `_expr`, `_decl`, `_proc`, `_name`, `_prog`) and nothing in
`lexer.inc` participates. So this is entirely inside Track P's carved-out files
and needs no Track A change — which also means it does not collide with an
agent holding A or O.

**Inferred, NOT verified — treat as a lead, not a finding.**
`DelphiRewriteGenericUses` (`pasparser_generic.inc:445`) sweeps the token stream
per template from a `var insertAt` cursor, run to a fixed point by its caller at
line 905, and its own header comment says the ordering requirement is that each
round's aliases land after the previous round's *"since an outer alias refers to
an inner one"*. A specialization group that only comes into existence during a
later instantiation is exactly the case that ordering has to cover. I did not
instrument this and I am not asserting it: the repo's own history is that a
plausible story recorded as a cause is the expensive failure here, and the last
entry in the rung ticket above is itself a corrected wrong root cause. Whoever
takes it should instrument the sweep (`PXXDBG`) rather than build on this
paragraph.

## Lead (UNMEASURED) — possibly the same defect as the parked ordering ticket

Recorded by the coordinator on frankA's suggestion, **labelled as a lead because
nobody has measured it.** frankA, which parked the earlier generics-ordering
ticket on this rung, reads this one as *possibly the same defect family seen from
a cleaner angle*.

Worth one check before anyone opens a second diagnosis: **if they are the same
mechanism, this is the ticket to work**, because its repro is 14 lines with fpc
3.2.2 accepting *both* orderings — an oracle on the passing arm as well as the
failing one — where the parked ticket's starting position is worse. frankA said
so itself.

If they are **not** the same, say so here explicitly rather than leaving the lead
open. An unresolved "these might be one thing" note is the shape that gets
believed later: it reads as prior investigation and is not.
