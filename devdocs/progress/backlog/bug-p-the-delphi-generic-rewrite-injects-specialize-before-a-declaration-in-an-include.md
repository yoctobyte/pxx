---
prio: 55
track: P
type: bug
status: backlog
blocked-by: []
found: 2026-08-30
found-by: frankA
summary: "In {$MODE DELPHI}, a generic type DECLARATION that arrives through an {$I} include is rewritten as if it were a generic USE: the sweep injects `specialize` in front of `TPair<TKey, TValue> = record`, and the parse dies with `unexpected token`. Same declarations written inline compile clean, so the include boundary is the trigger."
---

# The Delphi generic rewrite injects `specialize` before a DECLARATION that came from an `{$I}` include

## Repro — 11 lines of unit source

`u_tmpl.pas`:

```pascal
unit u_tmpl;
{$MODE DELPHI}
interface
type
  IComparer<T> = interface
    function Compare(constref L, R: T): Integer;
  end;
implementation
end.
```

`inc/decls.inc`:

```pascal
  TPair<TKey, TValue> = record
    Key: TKey;
    Value: TValue;
  end;

  TCustomDict<TKey, TValue> = class
  public type
    TDictionaryPair = TPair<TKey, TValue>;
  private var
    FEqualityComparer: IComparer<TKey>;
  end;
```

`u_use.pas`:

```pascal
unit u_use;
{$MODE DELPHI}{$H+}
{$MACRO ON}
interface
uses u_tmpl;
type
{$I inc/decls.inc}
implementation
end.
```

Compiled by a `program drv; uses u_use; begin end.`:

```
pascal26:1: error: unexpected token
  in: .../inc/decls.inc
  near: interface uses u_tmpl  type specialize >>> TPair  TKey
```

## What the token stream shows

`specialize` appears **before `TPair`**, in a position where the source has a
generic type *declaration*. The Delphi→objfpc rewrite has classified
`TPair<TKey, TValue> = record` as a *use* of a generic rather than a
declaration of one, and injected the objfpc specialization keyword in front of
it.

## The include boundary is the trigger, measured

The identical declarations written **inline** in `u_use.pas` compile clean.
Five progressively closer inline variants were tried and all five pass:

1. plain cross-unit `IComparer<TKey>` field
2. `+ constref` in the template's method
3. `+` a method implementation taking `IComparer<TKey>`
4. `+` a macro-supplied parameter list (`{$DEFINE MAP_CONSTRAINTS := TKey, TValue}`)
5. `+` nested `public type` / `private var` sections

Only moving them into an `{$I}` include fails. This fits the durable fact
recorded on [[feature-pascal-corpus-expansion]]: **`Tokens[]` is one array
shared by every unit**, and anything that reads a token INDEX across a boundary
has to survive that. An include is another such boundary.

## Relationship to `625991d20`, and it is NOT a regression

`625991d20` (2026-08-29) moved the sweep to desugar from the USES clause rather
than from the template, closing
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]]. On this
repro the two binaries fail **differently**:

```
PINNED (pre-fix) : pascal26:6: error: unknown type: TKey
HEAD  (post-fix) : pascal26:1: error: unexpected token ... specialize >>> TPair
```

Both fail, so **no working case was broken** — the failure mode moved. Worth
stating plainly because the error text changed completely, and the new one
points at the include rather than at the specialization.

## Why it matters

This is the wall now standing between the corpus ladder and
`generics.collections` (rung 6+ of [[feature-pascal-corpus-expansion]]).
Bisecting that 4165-line unit lands on exactly one line —
`{$I inc\generics.dictionariesh.inc}` — and that include declares
`TPair<TKey, TValue>` in precisely this shape.

## Where to start — and what NOT to start from

Start at the rewrite's declaration-vs-use test, and ask how it behaves when the
tokens it is scanning came from an include. **Do not** start from the corpus's
surface error (`unknown type: TKey`): that is the *old* wall's text, it names a
type parameter that is a red herring, and the five reductions above show the
specialization itself is fine.

Care is needed not to re-widen
[[bug-a-the-delphi-generic-rewrite-is-not-idempotent]], which is the recorded
hazard on this same rewrite.
