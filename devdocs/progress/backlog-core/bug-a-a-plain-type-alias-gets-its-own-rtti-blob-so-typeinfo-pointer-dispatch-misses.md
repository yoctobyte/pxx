---
track: A
prio: 30
type: bug
blocked-by: []
summary: "WIDENED 2026-09-06 BY CENSUS at 0e3558e5a4d4: pxx has NO alias identity mechanism at all. Filed as `type TMyInt = Integer` minting its own RTTI blob; measured across six spellings, pxx answers DIFFER on EVERY row -- plain scalar alias, synonym (LongInt vs Integer), alias of an ENUM, of a STRING and of a RECORD -- where fpc 3.2.2 answers SAME on all five. Every named type mints its own descriptor. THE ONE ROW PXX GETS RIGHT (`= type Integer`, which SHOULD differ) IT GETS RIGHT BY HAVING NO OPINION, so it is the obvious control, it passes today, and it passes after a wrong fix too -- do not use it as the control; the five SAME rows discriminate. Breaks the standard RTTI dispatch idiom `if p = TypeInfo(Integer)`: a variable declared through an alias matches NOTHING while name and kind both say it should. SELF-INCONSISTENT, NO ORACLE NEEDED. TWO FURTHER DEFECTS FROM THE SAME CENSUS: (1) an alias of an ENUM yields an INTEGER header (Kind=1, name "Integer") instead of the enum blob, so GetEnumName gets a header where its PEnumRTTI signature says blob -- a second live instance of bug-a-typeinfo-does-not-return-one-shape-of-pointer, reached by an ordinary alias rather than a subrange; (2) an alias of a RECORD yields Kind=13 and SEGFAULTS on its own NamePtr. NOT frankS's variable path, which is correct. CORRECTS A PREMISE IN decide-typeinfo-scalar-name-spelling (the label is identical and the behaviour differs, exactly inverting its dismissal of option 3); that decision is about the NAME STRING and is NOT reopened."
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

## Provenance

Found while probing the keyword-vs-identifier spelling seam
(`refactor-p-five-dispatch-sites-for-one-named-type-cast`); it is not that seam —
both spellings resolve correctly.

**The original filing said "not mine to touch while frankS is in the file". That
is no longer true and the sentence is replaced rather than left standing:** frankS
and I agreed it is ONE question with two holders, the census below was run once
to answer both halves, and this ticket is now frankA's. The reciprocal half is
[[bug-a-typeinfo-does-not-return-one-shape-of-pointer]] and neither should be
fixed without reading the other — they meet in the same table.

## The census — 2026-09-06 at `0e3558e5a4d4`, and it widens the ticket

Run once to answer this ticket's identity question and the shape question in
[[bug-a-typeinfo-does-not-return-one-shape-of-pointer]] together. Pointer
comparison only, no field reads, so it compiles under both compilers.

| spelling | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `TMyInt = Integer` (plain alias) | SAME | **DIFFER** |
| `TMyInt2 = type Integer` (distinct) | DIFFER | DIFFER |
| `LongInt` vs `Integer` (synonym) | SAME | **DIFFER** |
| `TMyColour = TColour` (alias of ENUM) | SAME | **DIFFER** |
| `TMyStr = string` (alias of string) | SAME | **DIFFER** |
| `TMyRec = TRec` (alias of RECORD) | SAME | **DIFFER** |

**pxx answers DIFFER on every row.** So the defect is not "a plain scalar alias
mints a blob" as filed — **there is no alias identity mechanism at all**: every
named type mints its own descriptor, for every type family.

**And the one row where pxx agrees with fpc, it agrees with by having no
opinion.** `= type Integer` is *supposed* to differ, and pxx gets it right
because it cannot tell that row from any other. That row is the obvious control
for a fixer to reach for, it passes today, and it will pass after a wrong fix
too — it can only fail if identity collapses too far. **Do not use it as the
control.** The discriminating rows are the five that should say SAME.

## Two further defects the same census turned up

Both are self-inconsistent and need no oracle.

**1. An alias of an ENUM reports as an INTEGER header.** `TypeInfo(TMyColour)`
where `TMyColour = TColour` yields a TTypeInfo header with `Kind` = 1 and
`NamePtr^` = `"Integer"` — not an enum blob, and not named for anything the
program declared. `TColour` itself correctly yields the enum blob. So the alias
does not merely mint a *separate* descriptor, it mints a descriptor **of the
wrong shape and the wrong kind**, and `GetEnumName(TypeInfo(TMyColour), 0)` is
handed a header where its `PEnumRTTI` signature says blob. That is a second live
instance of the shape bug, distinct from the subrange one already recorded
there, and it is reached by an ordinary alias rather than by a subrange.

**2. An alias of a RECORD yields a header whose `NamePtr` is unreadable.**
`TypeInfo(TMyRec)` gives `Kind` = 13 (correct for a record) and then
**segfaults** on `NamePtr^`. `TRec` itself reads fine. A descriptor that
type-checks, reports the right kind, and crashes on its own name field is worse
than the identity miss this ticket was filed for, because the identity miss is
at least silent and recoverable.

**The probe must read `Kind` before `NamePtr` or it dies mid-census.** The first
cut did not and segfaulted on row 6, reporting nothing about rows 7–13 — where
both defects above live. A probe that dies partway through reads as a short
table, not as an error.
