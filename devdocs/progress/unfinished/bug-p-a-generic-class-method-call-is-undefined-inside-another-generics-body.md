---
prio: 60
track: P
owner: frankA
status: working
---

# `TGeneric<T>.ClassMethod` is "undefined variable" inside another generic's body

- **Type:** bug (spurious error on a valid construct) — **Track P** (Pascal
  frontend, generics).
- **Pre-existing:** reproduces identically on **pinned**.
- **Found by:** compiling `rtl-generics` (corpus rung 6) — see
  [[feature-pascal-corpus-expansion]]. Second of the two Track P walls in
  `generics.defaults.pas`; **not** typinfo.
- **Binary:** `2c4e727d4b63`, verified self-host fixedpoint at `4f380892c`.
- **Sibling:**
  [[bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class]].

## Symptom

Calling a class method on a generic that is specialized *inline* by the
**enclosing** generic's own type parameter — `TCmp<T>.Default` written inside
the body of `TOrd<T, U>` — is rejected with `undefined variable (TCmp)`. The
name is read as a variable rather than as a type being specialized, so the
`<T>` is never consumed.

## Repro (24 lines; FPC prints `8`, pxx errors)

```pascal
program s1;
{$MODE DELPHI}{$H+}
type
  TCmp<T> = class
    class function Default: LongInt; static;
  end;

  TOrd<T, U> = class
    class function Get: LongInt; static;
  end;

class function TCmp<T>.Default: LongInt;
begin
  Result := SizeOf(T);
end;

class function TOrd<T, U>.Get: LongInt;
begin
  Result := TCmp<T>.Default;   // <-- pascal26: undefined variable (TCmp)
end;

type TO1 = TOrd<Int64, LongInt>;
begin
  WriteLn(TO1.Get);
end.
```

## Why it matters

This is the standard way `rtl-generics` reaches a comparer:

```pascal
class constructor TOrdinalComparer<T, THashFactory>.Create;
begin
  FEqualityComparer := TEqualityComparer<T>.Default(THashFactory);
  FComparer := TComparer<T>.Default;
end;
```

13 expression-position uses in `generics.defaults.pas`; the shape appears
~357 times across `generics.collections.pas`, so it is very likely the dominant
wall on rung 6's larger unit as well. Worth confirming that count against
`generics.collections.pas` once this and the sibling are fixed — that grep
counts implementation headers too, which are fine.

## Note on scope

`TCmp<T>.Default` where `T` is a *concrete* type resolves fine. The failure
needs `T` to be the enclosing generic's parameter, i.e. the specialization is
itself still a template at the point of use.

---

## Diagnosis banked, ticket parked (2026-08-28, frankA)

Reproduced, root-caused, and **reclassified** — but not fixed. Parking with the
diagnosis rather than landing a microfix, per `root-cause-over-microfix.md`. All
speculative edits were reverted; the tree is at a verified fixedpoint
(`c264c81a0d5a`) with no partial work in it.

### This is not a Delphi-surface bug, and the ticket title understates it

The decisive measurement: the same construct written by hand in **objfpc**, with
no Delphi rewrite involved anywhere, fails **on the pinned binary**:

```pascal
{$mode objfpc}{$H+}
type
  generic TCmp<T> = class
    class function Default: LongInt; static;
  end;
  generic TOrd<T, U> = class
    class function Get: LongInt; static;
  end;
class function TCmp.Default: LongInt; begin Result := SizeOf(T); end;
class function TOrd.Get: LongInt;
begin
  Result := (specialize TCmp<T>).Default;   { pinned: undefined variable (specialize) }
end;
type TO1 = specialize TOrd<Int64, LongInt>;
begin WriteLn(TO1.Get); end.
```

So the real defect is: **a nested `specialize X<T>` group is not supported in
EXPRESSION position.** Parenthesised or bare, both fail. The mode-Delphi
spelling merely reaches it by a different route and reports a different message.
Retitle when picking this up.

### Two stacked defects, in order

**(a) The rewrite misclassifies the use as a method-impl header.**
`DelphiRewriteGenericUses` (`pasparser_generic.inc`) decides "is this a method
implementation header?" by testing what **follows** the group — a dot:

```pascal
if (j + 1 < TokCount) and (Tokens[j + 1].Kind = tkDot) then
  RemoveTokens(i + 1, j - i)   { method impl reference }
```

But `TCmp<T>.Default` in expression position also has a dot after the group, so
it is treated as a header and has its `<T>` deleted — leaving a bare template
name, hence `undefined variable (TCmp)`. A header is identified by what
**precedes** the name (`procedure` / `function` / `constructor` / `destructor`,
optionally after `class`), not by what follows it. Note `constructor` and
`destructor` are SOFT keywords here — compared by text, delivered as `tkIdent`
(`pasparser_class.inc:26`).

Correcting this alone is *not* a fix: it routes the use into the `specialize`
arm, where it then hits (b) and reports `undefined variable (specialize)`. That
is the honest state — both surfaces converge on the same underlying gap — but it
is not a user-visible improvement, which is why it was not landed on its own.

**(b) The nested-specialization prerequisite scan never looks inside method
bodies.** In `ParseSpecialization`, the scan that collects nested
`specialize NAME<args>` prerequisites sweeps only:

```pascal
ts := Templates[ti].TokStart;
tc := Templates[ti].TokCount;
```

i.e. the **class body**. Method bodies are buffered separately by
`BufferGenericMethod` into `GenericMethods[]`. A nested specialization that
appears *only* inside a method is therefore never registered, no alias
declaration is emitted, `SpecializeStream`'s collapse finds `NestedSpecKnown`
false, and the literal word `specialize` survives into the stream — which is
exactly the error text.

### What was tried, and where it stopped

Extending the scan to `for gmScan := -1 to GenericMethodCount - 1` (−1 = class
body, ≥0 = each buffered method with `TemplateIdx = ti`) **does** change
behaviour — the prerequisite is created and the alias declaration is emitted —
but the streamed alias then fails differently:

```
error: expected method name    near: Int64  class class function >>> Default
```

i.e. the alias's own class body streams as
`TCmp$Int64 = class class function Default: LongInt; static; ... end;` and the
class-body parser rejects the `class function` member in that position, even
though the identical member parsed fine in the original template. That is a
third thing, not understood, and chasing it is where this stopped.

**So the scan extension is necessary but not sufficient.** Anyone picking this
up should expect to fix (a), (b), and whatever that third failure is, and should
treat the objfpc repro above as the primary case — it is smaller, has no rewrite
in the way, and fails on `pinned`.

### Not to be confused with

[[bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class]]
(fixed, `042bcbb32`) touched the same arm of the same function but is a
different defect: that one was about *which class* a genuine header binds to;
this one is about a use that is not a header at all.

**Status:** unfinished — diagnosis banked, no partial code landed.
