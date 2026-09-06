---
slug: bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization
title: "A nested specialization is minted under its ALIAS name, so specializing the outer class twice collides -- warnings on fgl, a hard type error on a reduction"
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`TEnumSpec = specialize TEnum<T>` inside a generic class is minted under the ALIAS name, not under a name carrying the type argument, and `NestedSpecKnown` tests only that name. So `specialize TList<Integer>` and `specialize TList<String>` in one program both mint a class called `TEnumSpec`: `duplicate definition of 'TEnumSpec.GetCurrent'; the later body wins`. On real fgl (two TFPGList instantiations) that is three warnings and the program still runs; on a two-line reduction it is a hard `incompatible types: cannot assign Integer to AnsiString` and legal code is refused. Pre-existing -- pin v404 warns identically."
---

# The shape

```pascal
unit unest7; {$mode objfpc}
interface
type
  generic TEnum<T> = class(TObject)
    V: T;
    function GetCurrent: T;
  end;
  generic TList7<T> = class(TObject)
  type
    TEnumSpec = specialize TEnum<T>;     { <- named by the ALIAS }
  public
    function Mk: TEnumSpec;
  end;
implementation
function TEnum.GetCurrent: T; begin Result := V; end;
function TList7.Mk: TEnumSpec; begin Result := TEnumSpec.Create; Result.V := 9; end;
end.
```

```pascal
program tnest8; {$mode objfpc}
uses unest7;
type
  TI = specialize TList7<Integer>;
  TS = specialize TList7<String>;    { DIFFERENT type argument -- second mint }
var a: TI; b: TS;
begin a := TI.Create; b := TS.Create; WriteLn(a.Mk.GetCurrent); end.
```

```
pascal26:0:  error: incompatible types: cannot assign Integer to AnsiString
pascal26:15: warning: duplicate definition of 'TEnumSpec.GetCurrent' with the same
             parameter types; the later body wins, but calls written between the two
             bind to the earlier one
```

**Legal code is refused.** One instantiation alone compiles and runs; adding a
second with a different type argument breaks the first.

# Mechanism

`ScanRangeForNestedSpecs` registers the prerequisite under
`aliasNm := NestedSpecAlias(...)` — the alias as written — and both guards are
name-only:

```pascal
if (not CaseEqual(aliasNm, specName)) and (not NestedSpecKnown(aliasNm)) then
  for k := 0 to NSpecCount - 1 do
    if CaseEqual(NSpecName[k], aliasNm) then dup := True;
```

```pascal
function NestedSpecKnown(const nm: AnsiString): Boolean;
begin Result := (FindSpecialization(nm) >= 0) or (FindUClass(nm) >= 0); end;
```

So the name `TEnumSpec` identifies the nested specialization **globally**, with
nothing in it derived from the argument the outer class was specialized on. The
outer template's body is streamed once per outer specialization and each pass
mints a member set under that one name.

This is the same collision-with-a-legal-value trap the alias table's own
`AliasOwnerCi` comment describes, and the same one `SPEC_HOST_NONE = -2` was
chosen to avoid: **a key that cannot distinguish the things it is used to look
up.** Here the key is a name and the thing it must distinguish is the type
argument.

# Severity depends on the arguments, which is why it reads as harmless

| corpus | result |
| --- | --- |
| real `fgl.pp`, `TFPGList<Integer>` + `TFPGList<String>` in one program | 3 warnings (`TFPGListEnumeratorSpec` `.GetCurrent`/`.Create`/`.MoveNext`), **compiles, runs, correct output** |
| the reduction above | **compile error**, legal program refused |

fgl survives because the merged bodies happen to stay type-compatible there. That
is luck, not a property — and it is exactly the shape that makes this look like a
cosmetic warning. `for i in list` over the wrong enumerator body is a silent
wrong answer waiting for the right pair of type arguments.

# Not caused by recent work

pin v404 prints the same warnings on the same fgl program. Found while looking at
a warning frankA saw on an unrelated reduction.

# What to measure first

Whether the fix is a NAME (mint `TEnumSpec$Integer` and add
`TEnumSpec -> TEnumSpec$Integer` to the substitution set in force while that
outer specialization's body is streamed) or a SCOPE (register the nested type
against the specialized owner, as `AddNestedType(ownerCi, ...)` already does for
in-body nested types, and resolve it through the owner rather than globally).
The name route is smaller and matches how `SpecializeStreamAt` already renames;
the scope route is the one that stops the global namespace growing a row per
nested type per instantiation.

Either way the guard has to be keyed on `(alias, argument list)` — the pair the
diagnostic already proves is not currently distinguished.

## A warning for whoever reduces this further

The reduction in this ticket fails at COMPILE time, which is the easy case. The
`fgl` arm does not — it compiles, runs, and prints the right answer with the
duplicate warning showing. **So any smaller reduction that runs rather than
refusing has to be built to discriminate, and two ordinary choices both hide
it:**

- **Do not assert the FIRST field of the inner class.** Offset 0 is what a lost
  or wrongly-bound base resolves to, so the first member is the one that cannot
  tell a correct read from a broken one. Give the inner class at least two
  fields and read the SECOND. (frank-optimize's rule, banked `5b93e5046`; it is
  the same shape as the "expected value collides with the default" rule this
  file already carries.)
- **Do not specialize the outer on two type arguments of the same width.**
  `<Integer>` and `<LongInt>` merge into a body that is wrong and harmless.
  The pair has to differ in a way the merged body cannot survive — which is why
  `<Integer>` against `<String>` is the pair in the reduction above, and why
  fgl's own `TFPGList<Integer>` + `TFPGList<String>` still runs correctly: the
  two enumerator bodies it merges happen to stay compatible.

Both are the same question asked of a reduction rather than of a guard: **if the
machinery did nothing at all, would this row still pass?**
