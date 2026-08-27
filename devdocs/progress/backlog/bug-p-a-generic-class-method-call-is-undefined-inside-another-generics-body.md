---
prio: 60
track: P
owner: unassigned
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
