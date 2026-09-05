---
slug: bug-p-a-generic-parameter-constraint-is-counted-as-a-type-body
track: P
prio: 55
type: bug
status: done
blocked-by: []
summary: "FIXED. A generic parameter CONSTRAINT put a real tkClass or tkRecord token in DGenDeclAnchor's path -- `TBoxB<T: class>`, `TRecB<T: record>` -- and each opens nothing and has no `end`, so an EARLIER template's anchor walk was left permanently one deep per later template it crossed, ran past the type section it exists to stop at, and spliced the minted alias inside a routine body. `<T: constructor>` did not reproduce, only because `constructor` reaches a different arm of the same walk. Fixed by skipping the whole `< ... >` group -- a generic parameter list is not a type body, so nothing in it may feed the depth count -- rather than special-casing each keyword, which would have left the third spelling to be found separately later. Sibling of bug-p-a-method-pointer-type-derails-the-delphi-generic-alias-anchor and found while fixing it; recorded as an open residual in that ticket first, then measured. NOT a regression from b613b5fcf's successor: reproduces on 1ea430c95 and under the pin."
owner: frankB
---

# A generic parameter constraint is counted as a type body

## Found by not trusting the sentence I had just written

While fixing [[bug-p-a-method-pointer-type-derails-the-delphi-generic-alias-anchor]]
I noticed that `<T: class>` reaches the same `tkClass` arm of `DGenDeclAnchor`
and that `DGenClassOpensBody` answers true for it. Every arm of that fix's test
passed, so it was masked, and I recorded it in that ticket as *"not measured, not
claimed, and not fixed in this commit"* rather than either asserting it or
dropping it. It is real:

```pascal
{$MODE DELPHI}
type
  TArg   = class end;
  TBoxA<T: class> = class class function Who: Integer; end;
  TBoxB<T: class> = class class function Who: Integer; end;   { crossed by A's walk }
  TLate  = class end;                                          { A's alias must name this }
```

```
pascal26:19: error: expected 'begin' before 'TBoxA$TLate'
  near: Result := 1 ; end ; >>> TBoxA$TLate  specialize
```

fpc 3.2.2 prints `1 2`.

## The three spellings are one concept, and only two of them broke

| constraint | reproduces |
| --- | --- |
| `<T: class>` | **yes** — tkClass, `DGenClassOpensBody` says it opens a body |
| `<T: record>` | **yes** — tkRecord, counted unconditionally |
| `<T: constructor>` | no — `constructor` reaches the section-ender arm instead |
| `<T>` unconstrained | no — nothing to miscount |

Ablated rather than reasoned: with the later template's constraint removed the
identical program compiles and prints `1 2`. A `<T: TArg>` spelling produces a
genuine, correct constraint-violation error and is NOT evidence either way —
recorded because it looked like a third data point for a minute and is not one.

## Fix

Skip the whole `< ... >` group. A generic parameter list is not a type body, so
nothing inside it may feed the body-depth count — which covers all three
spellings, and the argument form (`TBox<TArg>`) for the same reason.

`DGenAngleGroupEnd` is deliberately conservative about what it will call a
group: preceded by an identifier, containing nothing but identifiers, `,` `:`
`.` and the two constraint keywords that are token kinds, nesting counted so
`TBox<TBox<T>>` closes. Anything else — notably a real `<` comparison — returns
-1 and the walk behaves exactly as before.

**Special-casing each keyword was the alternative and is worse**, for the reason
this walk has now demonstrated three times: its keyword list has been wrong three
times in three different directions, and the fourth spelling would have been
found separately, later, by someone else.

## Test

`test/test_delphi_generic_constraint_anchor.pas`, `.expected` is fpc 3.2.2's own
output. Six arms: `class`, `record` and `constructor` constraints; an
unconstrained later template and no later template at all as negative controls;
and arm 5 as the control for the fix's own risk — a real anonymous
`record ... end` field whose body must still be counted.

**Arm 5 was verified to discriminate rather than assumed to.** Built with
`tkRecord` never counted — the tempting wrong fix, since a constraint's `record`
reaches that arm — arm 5 fails:

```
pascal26:125: error: expected ':'
  near: : Integer ; end ; TBox5$TLate5 >>>  specialize TBox5
```

the alias spliced into the record. And the whole file fails on the pre-fix
compiler at arm 1.

**What the test does NOT cover, stated so nobody trusts it to:** the skipper
being too WIDE about what it calls a `< ... >` group. Nothing in this file has a
`<` that is not one, so a widened skip passes every arm. That guard lives in
`DGenAngleGroupEnd`'s token filter and is argued there, not tested here.

## Not a regression

Reproduces on `1ea430c95` and under the pin. `b613b5fcf` introduced the walk, so
this shipped with it; unlike its `of object` sibling it did not break a corpus
rung, which is why it survived undetected.
