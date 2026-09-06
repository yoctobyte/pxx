---
track: A
prio: 30
type: bug
blocked-by: []
summary: "MEASURED 2026-09-06 at 4d0642bfa917. `type TMyInt = Integer` mints its OWN RTTI blob, so `TypeInfo(TMyInt) <> TypeInfo(Integer)` while both blobs carry the SAME name (`Integer`) and the SAME kind (1) -- two descriptors for one type. FPC answers SAME (a plain alias is the same type there; only `= type Integer` makes a distinct one). It breaks the standard RTTI-keyed dispatch idiom `if p = TypeInfo(Integer)`: a variable declared through the alias matches NOTHING, silently, and every name/kind inspection says it should have matched. SELF-INCONSISTENT SO IT NEEDS NO ORACLE -- same name, same kind, different identity. NOT frankS's variable path, which is correct: TypeInfo(m) = TypeInfo(TMyInt) and TypeInfo(i) = TypeInfo(Integer) both hold; the divergence is in the TYPE-NAME path and the pin cannot reach the variable form at all. CORRECTS A PREMISE IN decide-typeinfo-scalar-name-spelling, which argued option 3 'buys nothing here -- the observable behaviour is already identical and only the RTTI label differs'. Here the LABEL IS IDENTICAL AND THE BEHAVIOUR DIFFERS, exactly inverted. That decision is about the NAME STRING and is not reopened by this."
status: backlog
owner: unassigned
---

# A plain type alias gets its own RTTI blob, so `TypeInfo` pointer dispatch misses

## Repro

```pascal
program p;
uses typinfo;
type TMyInt = Integer;
begin
  WriteLn(PTypeInfo(TypeInfo(TMyInt))^.NamePtr^, ' ', PTypeInfo(TypeInfo(TMyInt))^.Kind);
  WriteLn(PTypeInfo(TypeInfo(Integer))^.NamePtr^, ' ', PTypeInfo(TypeInfo(Integer))^.Kind);
  if TypeInfo(TMyInt) = TypeInfo(Integer) then WriteLn('SAME') else WriteLn('DIFFER');
end.
```

pxx at `4d0642bfa917`:

    TMyInt  name=Integer kind=1
    Integer name=Integer kind=1
    ptr TMyInt=Integer DIFFER

**Same name, same kind, different pointer.** FPC 3.2.2 answers `SAME`.

## Why it matters — the dispatch idiom, not the string

The reason RTTI carries an identity at all is so code can key on it:

```pascal
if p = TypeInfo(Integer) then ...
```

With `var m: TMyInt`, `TypeInfo(m)` matches **neither** `TypeInfo(Integer)` nor
`TypeInfo(LongInt)` nor `TypeInfo(Int32)` — it matches nothing in the program,
while `^.NamePtr^` and `^.Kind` both say it is an `Integer`. A serializer, a
variant registry or a property dispatcher written the ordinary way takes the
fall-through arm and is wrong with no diagnostic.

`type TMyInt = Integer` is a plain ALIAS. In FPC a distinct type needs
`type TMyInt = type Integer`, and standard Pascal agrees an alias names the same
type — so code expecting these equal is correct code, which is what makes this a
bug rather than a compat entry.

## What is NOT the cause

**frankS's `TypeInfo(variable)` work (`14e6ce592`) is correct and is not
implicated.** Measured on the same binary:

| question | pxx | fpc |
| --- | --- | --- |
| `TypeInfo(m)` vs `TypeInfo(TMyInt)` | SAME | SAME |
| `TypeInfo(i)` vs `TypeInfo(Integer)` | SAME | SAME |
| `TypeInfo(TMyInt)` vs `TypeInfo(Integer)` | **DIFFER** | SAME |

The variable resolves to exactly its own declared type in every case. The
divergence is entirely in the TYPE-NAME path, which predates that commit — the
pinned compiler refuses `TypeInfo(m)` outright, so the variable form could not
have introduced it.

**Nor is it the `tyInteger`/`tyInt32` split.** That is
`decide-typeinfo-scalar-name-spelling`'s option 3 and a separate, larger
question. This defect reproduces *within* one kind: `TMyInt` and `Integer` are
both `tyInteger`, both named `Integer`, and still have different identities.
Collapsing `tyInteger` into `tyInt32` would not fix it.

## The premise it corrects

`decide-typeinfo-scalar-name-spelling` (decided, user, 2026-08-21) dismisses its
own option 3 with:

> option 3 ... buys nothing here — the observable behaviour is already identical
> and only the RTTI label differs.

That sentence is now falsified in the exact opposite direction: **the label is
identical and the behaviour differs.** The decision itself — keep `Integer` by
default, report `LongInt` under `--strict-fpc` — is about the NAME STRING, is
unaffected, and is NOT reopened here. Only the supporting claim that nothing
observable differs is wrong, and it is the sentence a future reader would use to
dismiss this ticket.

## Where to look

The alias category of the TypeInfo request table (`RegisterTypeInfoReq`,
`TYPEINFO_REQ_CAT_ALIAS`, `compiler/pasparser_expr.inc` ~4519 and
`compiler/rtti_emit.inc`). A plain scalar alias whose target is a builtin should
resolve to the TARGET's blob rather than minting a row. Not attempted here.

**Check before fixing:** a `= type Integer` distinct-type spelling, if pxx has
one, must keep its own blob — that is the shape the current behaviour is right
for, and a fix that collapses both is trading one wrong answer for another.
`test/test_typeinfo_named_types.pas` asserts `TypeInfo(TMyInt)` prints
`Integer`, which a correct fix leaves green.

## Not taken

Found while probing the keyword-vs-identifier spelling seam
(`refactor-p-five-dispatch-sites-for-one-named-type-cast`); it is not that seam —
both spellings resolve correctly. Left unfixed because frankS is actively in
`rtti_emit`/TypeInfo and this is one question with two possible holders, not a
file conflict git would show.
