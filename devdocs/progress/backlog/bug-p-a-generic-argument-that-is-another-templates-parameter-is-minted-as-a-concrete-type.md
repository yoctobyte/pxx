---
slug: bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type
track: P
prio: 65
type: bug
status: backlog
blocked-by: []
summary: "`TCmp<TKey>` written inside `TDict<TKey, TValue>`'s body is minted EAGERLY as the concrete alias `TCmp$TKey`, because DelphiRewriteGenericUses tests an argument only against the template it is currently rewriting (ti), and TKey belongs to the ENCLOSING template. The streamed class body then says `Val: TKey` and reports `unknown type: TKey` — pointing at the TEMPLATE's file, not the user's specialization. 15-line repro, FPC prints 5. Pre-existing on pinned. This is the ORIGINAL `unknown type: TKey` symptom of bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized, which turned out to be a second, independent defect."
owner: unassigned
---

# A generic argument that is another template's parameter is minted as a concrete type

Separated out of
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]] on
2026-08-29. That ticket was originally filed as *"a generic type parameter is
unknown when a specialization is materialised cross-unit"* from the corpus error
`unknown type: TKey`, then renamed on the grounds that the `TKey` framing *"was
wrong"*. It was not wrong — it was **this**, a second defect that the
eleven-line repro walked past because a different one sat in front of it. Fixing
that one leaves this one exactly where it was.

## Repro — 15 lines, FPC prints `5`, pxx errors on `pinned` and on HEAD

```pascal
program w;
{$MODE DELPHI}
type
  TCmp<T> = class
    Val: T;
  end;
  TDict<TKey, TValue> = class
    C: TCmp<TKey>;
    K: TKey;
  end;
var d: TDict<Integer, LongInt>;
begin
  d := TDict<Integer, LongInt>.Create;
  d.K := 5;
  WriteLn(d.K);
end.
```

```
pascal26:5: error: unknown type: TKey
  near: TKey   class Val  >>> TKey  end
```

Line 5 is `Val: T;` — inside **TCmp's** declaration, which is correct source.
The error is reported from the streamed body of `TCmp$TKey`, a class that should
never have been minted.

## Cause

`DelphiRewriteGenericUses` (`pasparser_generic.inc`) decides whether a
`<...>` group can be resolved eagerly into an alias by asking whether any
argument is one of **ti's own** parameter names:

```pascal
for k := 0 to na - 1 do
  for kk := 0 to np - 1 do
    if ... TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + kk] ... then
      isParamForm := True;
```

`TKey` is not one of `TCmp`'s parameters, so the group reads as concrete and is
minted. But it is not concrete: it stands for whatever the **enclosing**
template is specialized with, and belongs on the deferred / nested-prerequisite
path exactly like `TCmp<T>` inside TCmp's own body does.

## What does NOT fix it, measured

Widening that test to **any** template's parameter names was built, run, and
**backed out**: it changes nothing on this repro and nothing on
`generics.collections`. The reason is ordering — when TCmp's sweep runs, TDict
has not been parsed yet, so `TKey` is not any *known* template's parameter name.
The fixed point re-runs every template after TDict registers, but by then
`TCmp<TKey>` has already been rewritten to `TCmp$TKey` in round one. It also
costs nothing and buys nothing, so it is not worth carrying "just in case".

That rules out the cheap version. A real fix has to decide eligibility from
something that is true at round one — the obvious candidate being *"does this
argument name a type that resolves here?"*, which is a different question from
*"is it a parameter name"* and needs its own measurement, because a type
declared later in the same type section does not resolve at sweep time either.
**Direction, not diagnosis.**

## Corpus

This is the current stop for `uses Generics.Collections`:
`generics.collections.pas` writes `TComparer<TKey>` inside its dictionary
templates, and the error surfaces at `generics.defaults.pas:46` — a file the
user never wrote a specialization in, which is what made the original report so
hard to place. Byte-identical on `pinned`.

## Gate

The repro printing `5`; `generics.defaults.pas` keeps compiling alone; the
existing generic tests (19 named + 8 `.expected`) stay green; the reduction
lands in `test/`; the per-fix loop.
