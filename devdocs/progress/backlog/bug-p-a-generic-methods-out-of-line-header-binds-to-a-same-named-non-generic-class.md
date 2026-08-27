---
prio: 60
track: P
owner: unassigned
---

# A generic class's out-of-line method header binds to a same-named non-generic class

- **Type:** bug (wrong scope resolution, diagnosed as a spurious error) —
  **Track P** (Pascal frontend, generics).
- **Pre-existing:** reproduces identically on **pinned**, so it is not a
  consequence of the nested-type fixes (`7ee75329e`, `83468c546`).
- **Found by:** compiling `rtl-generics` (corpus rung 6) — see
  [[feature-pascal-corpus-expansion]]. This is one of the two Track P walls in
  `generics.defaults.pas`, and it is **not** typinfo.
- **Binary:** `2c4e727d4b63`, verified self-host fixedpoint at `4f380892c`.

## Symptom

When a generic class shares its bare name with a non-generic class it inherits
from, **and** both declare a method of the same name, the out-of-line
implementation header `TSvc<T>.Sel` is matched to the **non-generic** `TSvc`.
The body is then compiled in the wrong class's scope, so the generic's own
`class var`s are not visible and every reference to one is reported as an
undefined variable.

The compiler already tells you what it did — it emits, before the error:

```
warning: duplicate definition of 'TSvc.Sel' with the same parameter types;
the later body wins, but calls written between the two bind to the earlier one
```

i.e. it dropped the `<T>` from the header and saw two bodies for one method.

## Repro (33 lines; FPC prints `TRUE`, pxx errors)

```pascal
program r1;
{$MODE DELPHI}{$H+}
type
  TSvc = class
  private
    class function Sel: Pointer; virtual;
  public
    class function Run: Pointer;
  end;

  TSvc<T> = class(TSvc)
  private class var
    FInst: Pointer;
  private
    class function Sel: Pointer; override;
  end;

class function TSvc.Sel: Pointer;
begin
  Result := nil;
end;

class function TSvc.Run: Pointer;
begin
  Result := Sel;
end;

class function TSvc<T>.Sel: Pointer;
begin
  Result := @FInst;     // <-- pascal26: undefined variable (FInst)
end;

type TH = TSvc<LongInt>;
begin
  WriteLn(PtrUInt(TH.Run) <> 0);
end.
```

## Boundary — both halves are required

Varying one thing at a time isolates the trigger; each of these **passes**
today:

| shape | result |
| --- | --- |
| generic + non-generic same name, **different** method names | passes |
| generic class var, no name collision at all | passes |
| generic class var typed by a qualified nested type `TOuter.TInner` | passes |
| generic with a constraint `<T: TFactory>`, no name collision | passes |
| **same class name AND same method name** | **fails** |

So the defect is in matching an out-of-line header to its class: the arity
(`<T>`) is not part of the key, so a same-named non-generic class wins.

## Why it matters

This is the shape FPC's own `rtl-generics` uses for its service hierarchy —
`THashService<T: THashFactory> = class(THashService)` and
`TExtendedHashService<T: TExtendedHashFactory> = class(TExtendedHashService)`,
each overriding the non-generic parent's virtuals. Renaming just those two
generics in a scratch copy moved the compile from failing at line 2173 to
clearing the entire class hierarchy, so this one defect gates roughly 700 lines
of `generics.defaults.pas` on its own.

## Suggested direction

Include the generic arity in the key used to match an out-of-line method header
to its class, the same way the specialization machinery already distinguishes
`THashService` from `THashService<T>` at the *declaration* site (the declaration
side gets this right — only the implementation-header side does not). This is
the `normalise-dont-special-case` shape: one lookup that is arity-aware, not a
second path for generics.
