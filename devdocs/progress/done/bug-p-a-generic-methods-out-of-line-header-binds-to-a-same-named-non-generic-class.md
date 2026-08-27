---
prio: 60
track: P
owner: frankA
status: working
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

---

## Root cause — the rewrite deletes the disambiguator, then the resolver guesses

Not in the resolver, where the symptom is. `DelphiRewriteGenericUses`
(`pasparser_generic.inc`) turns the mode-Delphi header

```pascal
class function TSvc<T>.Sel: Pointer;
```

into the objfpc spelling `class function TSvc.Sel;` by **deleting** the `<T>`
group — and that group was the only thing distinguishing this header from the
impl of a same-named non-generic class's method. `ParseSubroutine` then has to
resolve ownership by name alone, and its existing tie-break ("ask which class
DECLARES this method") picks the ordinary class whenever both declare it. The
template's body is compiled in the wrong scope, so its class vars are undefined.

The tie-break itself is correct and stays: in **objfpc** the source really does
spell both headers `X.M` and they really are indistinguishable. That code
carried a comment asserting the ambiguity could not arise for generics —

> A `X<T>.M` header never reaches this branch (CurTok would be '<', not '.')

— which is true in objfpc and **false in mode Delphi**, because the rewrite runs
first. The comment has been corrected in place; it was load-bearing, and leaving
it would have re-authorised the same reasoning.

## Fix — record what the deletion throws away

`7 lines at the deletion site, 11 at the resolver.` Before `RemoveTokens`, push
the class-name token's `SOffset` onto `GenMethImplSOff` (`defs.inc`). At the
resolver, skip the by-name tie-break when the current header's class-name token
is in that table: the source said `<T>`, so the template is the answer by
construction rather than by inference.

Keyed on **SOffset**, a source character offset, not a token index — token
indices are not stable here, since `DelphiRewriteGenericUses` runs to a fixed
point once per template and every round can shift them via
`RemoveTokens`/`InsertTokens`.

Delphi-only by construction: objfpc source spells the header `X.M` itself,
nothing rewrites it, no entry is ever recorded, and the genuinely ambiguous
objfpc case resolves exactly as before.

## Verification

- Repro passes; FPC and pxx agree byte for byte.
- Regression test `test/test_generic_delphi_method_header_binds_to_the_generic`
  covers the failing combination **and** the two shapes that already worked
  (same class name with no method collision; a generic class var with no
  collision at all), so the fix cannot later be narrowed to only the broken case.
  It fails on `pinned` with `undefined variable (FBump)` and passes here.
- The four neighbouring shapes probed while isolating this — arity overload,
  constraint-only, qualified nested type as a class-var type, plain generic
  class var — all still pass.
- `make compiler/pascal26`: fixedpoint converged, `e82c2f63a242`.
- `tools/gate.sh quick`: GREEN.

## Effect on rung 6, measured not assumed

On `generics.defaults.pas` (typinfo stubbed, **no** renames) the wall moved from
line 2173 to **2351** — the whole `THashService<T>` class-var surface now
resolves. The new wall there is a different defect and is **not** typinfo
either:

```pascal
FEqualityComparerInstances[tkFile] :=
  TInstance.CreateSelector(TMethod(TSelectMethod(
    THashService<T>.SelectBinaryEqualityComparer)).Code);
```

`IR_UNSUPPORTED: frontend could not lower AST node (kind 88)` —
`AN_CLASS_VIRTUAL_CALL`, i.e. the **address** of a virtual class method taken as
a value and cast to `TMethod`, rather than called. To be filed separately; it
raises the rung-6 wall count from four to five and is worth noting as a pattern:
each wall cleared exposes the next, so the "complete set for this unit" claim in
[[feature-pascal-corpus-expansion]] was correctly hedged.

**Status:** done

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
