---
slug: bug-p-a-qualified-type-name-cannot-be-a-generic-argument
track: P
prio: 65
type: bug
status: backlog
blocked-by: []
summary: "`specialize TEnum<TOuter.TPair>` is rejected — `Expected: >, but got: .`. FPC compiles and runs it. A generic ARGUMENT is modelled as exactly one token everywhere in the frontend, and a qualified type name is three. Standalone 22-line repro, no nesting of generics involved. Also the blocker under bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument, whose remaining half needs to emit exactly this form."
owner: unassigned
---

# A qualified type name cannot be a generic argument

## Repro (FPC prints `5`, pxx does not compile)

```pascal
program q2;
{$mode objfpc}
type
  generic TEnum<T> = class
    V: T;
  end;

  TOuter = class
  type
    TPair = record
      K: Integer;
    end;
  end;

  TE = specialize TEnum<TOuter.TPair>;
var
  e: TE;
begin
  e := TE.Create;
  e.V.K := 5;
  writeln(e.V.K);
end.
```

```
Expected: >, but got:  (Kind: 81, Line: 15)
pascal26:15: error: unexpected token
  near: TE  specialize TEnum  TOuter >>>  TPair
```

Everything either side of this works and was probed separately, so the gap is
narrow and precisely placed:

- `x: TOuter.TPair` as an ordinary variable declaration compiles and runs (pxx
  and FPC both print `7 9`). Qualified nested type names are NOT the gap.
- `specialize TEnum<Integer>` obviously works. Single-token arguments are not
  the gap.

It is the ARGUMENT POSITION specifically.

## Root cause, and why the one-line version is the wrong fix

`IsConcreteTypeArgKind` (`pasparser_name.inc:80`) answers a question about **one
token kind**, and that shape has propagated into every place that reads an
argument list:

| site | what it assumes |
| --- | --- |
| `pasparser_generic.inc:1474` (`ParseSpecialization`) | one token, then `,` or `>` |
| `:96` (`NestedSpecGroup`) | ditto, over `TemplateTokens[]` |
| `:715` (`DelphiRewriteGenericUses`) | ditto, over `Tokens[]` |
| `:1889` | ditto |
| `NestedSpecArg` / `NestedSpecAlias` | an argument IS a `TRawToken`, singular |
| `NSpecArg[]` | `array[...] of TRawToken` — one slot per argument |
| `CollectSpecializationBoundNamesFromTokens` | one `SOffset`/`SLen` per name |

So the honest statement of the defect is not "the parser forgot dots". It is
**an argument is modelled as a token where the language says it is a type
reference**, and the token model is written into a storage type
(`NSpecArg: array of TRawToken`) as well as into five tests. Widening only
`ParseSpecialization` gets the declaration past the parser and then mints an
alias whose name came from `NestedSpecAlias`, which still read one token.

Sizing note for whoever takes it: the five `IsConcreteTypeArgKind` sites are the
cheap half. The argument-as-a-single-`TRawToken` storage is the half that
decides whether this is a microfix or a small refactor, and per
`devdocs/dev/root-cause-over-microfix.md` that call should be made deliberately
and written into this ticket, not discovered halfway.

## Why it matters beyond the repro

It is the **remaining half** of
`bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument`
(parked in `unfinished/` with the first half landed). That ticket's prerequisite
emitter currently writes `TEnum$TPair = specialize TEnum<TPair>` at the top
level, where `TPair` does not exist — it only exists inside
`TDict$Integer$LongInt`. The correct emission is the qualified form
`specialize TEnum<TDict$Integer$LongInt.TPair>`, which is exactly what this
ticket says the frontend cannot yet read. **Landing that ticket without this one
is not possible via the qualified route**, so the two want to be taken together
or the other route (hoisting a specialization's nested types to top-level
`$`-aliases) chosen deliberately instead. Both routes are open; neither has been
measured.

And `uses Generics.Collections` needs it: the stop at
`generics.collections.pas:120` is `TEnumerator<TDictionaryPair>` with
`TDictionaryPair` nested in the enclosing template — the same shape.

## Alias spelling is an open sub-question

Whatever route is taken has to name the result. `TEnum$TOuter.TPair` puts a `.`
inside a minted alias, and the minted-name scheme has so far only ever produced
`$`-joined identifier characters — `FindSpecialization`, `FindUClass` and the
class-binding path have never been asked to hold a dotted key. `TEnum$TOuter$TPair`
avoids that but can collide with a genuine two-argument specialization
`TEnum2<TOuter, TPair>` under a different arity. Decide it before minting, not
after a collision.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) + the repro
above + the existing generic tests named one by one. Track T sweeps the matrix.
