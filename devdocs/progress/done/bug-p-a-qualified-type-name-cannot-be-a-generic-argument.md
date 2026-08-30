---
slug: bug-p-a-qualified-type-name-cannot-be-a-generic-argument
track: P
prio: 65
type: bug
status: done
blocked-by: []
summary: "`specialize TEnum<TOuter.TPair>` is rejected — `Expected: >, but got: .`. FPC compiles and runs it. A generic ARGUMENT is modelled as exactly one token everywhere in the frontend, and a qualified type name is three. Standalone 22-line repro, no nesting of generics involved. Also the blocker under bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument, whose remaining half needs to emit exactly this form."
owner: frankP
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

## 2026-08-30 (frankP) — RESOLVED, both arms, and the control that narrowed it

**Route taken: NORMALISE, not widen.** The sizing note above asked for a
deliberate call between teaching six places about token ranges and something
smaller; the answer is neither of the two the ticket listed. A dotted argument is
consumed at the two places arguments are read and replaced by a single minted
identifier naming an ordinary type alias, and the alias declaration is emitted
through the prerequisite machinery that already exists. **Nothing downstream ever
sees a dot** — all five `IsConcreteTypeArgKind` sites, `NestedSpecAlias`,
`NestedSpecArg`, the `SpecSub*` set and `NSpecArg: array of TRawToken` are
untouched, so there is no second argument shape to keep in sync.

The target form was measured before it was built, not assumed:
`TAlias = TOuter.TPair;` followed by `specialize TEnum<TAlias>` already compiled
and ran identically on pxx and FPC.

**Alias spelling, the sub-question this ticket left open.** `$qual$TOuter$TPair`,
with a LEADING `$`. Plain `TOuter$TPair` is exactly what the specialization
minter emits for `TOuter<TPair>`, so under arity overloading the two would be a
real collision between different types — and a silent one. A leading `$` cannot
be produced by that minter and cannot be written in source, so the namespaces are
disjoint by construction rather than by convention. It is a synthetic `tkIdent`
compared only as a string, so the character never has to be lexable.

**Declared once per compilation, and the check is in ONE place.** The Delphi
rewrite reaches the emitter with duplicates by construction — one entry per
OCCURRENCE of the group, and it runs to a fixed point — while the objfpc path
filters earlier in `NoteQualArgNeed`. Two filters for one rule is how the second
goes stale, so the authoritative one sits inside `EmitQualAliasDecl`, which
nothing can skip.

## BOTH ARMS, because the sibling was broken and looked like this one

`normalise-dont-special-case.md`'s rule: fix one arm of a double case, grep for
the sibling before closing. mode Delphi has no `specialize` keyword and does not
go through `ParseSpecialization` at all — it goes through
`DelphiRewriteGenericUses`, whose `<...>` collector reads one token per argument
and simply failed to match, leaving the group alone: `unknown type: TBox`. Same
normalisation, second call site, aliases emitted at `insertAt` ahead of the tuple
declarations that name them.

## The control, which is the part worth keeping

The Delphi arm did NOT go green on the first try, and the reason was not this
ticket. Four probes separate the two effects:

| probe | mode | argument | declared | result |
| --- | --- | --- | --- | --- |
| q7 | delphi | `TOuter` | before the template | **works** |
| q5 | delphi | `TOuter` | AFTER the template | **fails** — nothing to do with dots |
| q6 | delphi | `TOuter.TPair` | before the template | fails → **this ticket**, now fixed |
| q4 | delphi | `TOuter.TPair` | AFTER the template | fails for BOTH reasons |

q5 is a separate pre-existing defect and is filed as
`bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template`
[P p55]: `DelphiRewriteGenericUses` splices its aliases immediately behind the
TEMPLATE, so they can name only what is declared by that point, while a Pascal
type section imposes no such order. Without q7 and q5 the honest-looking
conclusion from q4 alone is "qualified arguments still do not work in Delphi
mode", which is false and would have sent the fix in the wrong direction. The
wired Delphi test declares `TOuter` first and says in its header why, citing that
ticket.

## Tests

`test/test_generic_qualified_arg.pas` and
`test/test_generic_qualified_arg_delphi.pas`, 5 rows each, both wired into
`test-core`, oracle = FPC's output for those exact files (`total ok 5 / 5`).
Rows 2-5 are the traps, not padding: the same qualified type used twice (a second
alias emission would be a duplicate type declaration), two different outers whose
nested types share a last component (a mint keyed on the last component alone
would merge them), a second nested type of one outer, and an ordinary unqualified
argument that must be entirely unaffected.

Regression set: 25 named generic tests, 8 `.expected` clean, the rest identical
to `pinned`'s output except `test_generic_arg_is_enclosing_template_param` and
its objfpc arm, which differ because they are this session's earlier fix and both
match FPC. Self-host fixedpoint `5ff90e806e3c`, converged after 1 round.

## Not fixed by this, and named so nobody assumes otherwise

`bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument`
(`unfinished/`) named this ticket as its `blocked-by`, and the block is now
lifted — but that ticket is still RED. This supplies the machinery its remaining
half needs; it does not wire it in. Its prerequisite emitter still writes an
un-substituted nested name, verified after this landed.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) + the repro
above + the existing generic tests named one by one. Track T sweeps the matrix.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
