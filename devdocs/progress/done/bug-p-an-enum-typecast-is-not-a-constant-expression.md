---
slug: bug-p-an-enum-typecast-is-not-a-constant-expression
title: "A typecast to an enumerated type is not accepted in a constant expression"
track: P
prio: 45
type: bug
status: done
owner: ""
found-by: frankS
created: 2026-09-17
tags: [constant-expressions, enumerations, typecast, fpc-corpus]
blocked-by: []
summary: "FIXED 2026-09-17 in TWO arms, because the construct has two spellings. (1) 6eb1db8b4: ConstCastWidth gains an ENUM arm. pxx has no tyEnum -- an enum's values travel in an ordinary integer kind with the identity beside them in SymSemId -- so TypeIsOrdinal has no enum family and that door's alias arm could not answer for one however the enum was declared. The arm goes on the SOURCE-DECLARATION side of the order the door exists to own (a declaration outranks a builtin), and the width comes from EnumStorageTypeKind, the one place that says which kind an enum travels in -- not a re-derivation over the member list, or a {$PACKENUM}d enum would be cast at a different width here than everywhere else. That is what makes fpc's own cgbase.pas:401 shape come out right: tregister($ffffffff) -> -1 on a 4-byte SIGNED enum. (2) c86e8b29d: the same cast in a CASE LABEL. ParseCaseLabelValue has its own narrow grammar and its own comment already said it does not call the const-declaration evaluator -- the five intrinsics had been delegated for exactly that reason and the cast spelling was left behind. Delegated, not duplicated, so the alias-before-builtin order is decided in one place. test_const_enum_cast.pas, byte-identical to fpc 3.2.2 over eleven rows, with the K_ALIAS and K_BUILTIN order controls MID-FILE because a third arm inserted at the wrong point still passes every enum row, and the case-label rows AFTER the const rows because a reader who sees only the const rows is the reader who ships the one-armed fix. CORPUS: 22 / 10 / 175 -> 22 / 10 / 175, UNCHANGED -- the seventeenth consecutive null row, predicted as such before the run. All 14 units that had this as their first failure moved to TDoubleRec and not one converted, cgbase included. Do not read the 14 as a size; it was a queue position, as it has been seventeen times. INERT for lib/** until the next pin."
---

# Repro

```pascal
program r;
type TE = (a, b, c);
const K = TE(2);
begin WriteLn(Ord(K)); end.
```

| compiler | result |
| --- | --- |
| fpc 3.2.2 | compiles; prints `2` |
| pxx @ `efe06a903` | `pascal26:3: error: not a constant` |

## What is and is not the cause, isolated

The shape was found on an enum with explicitly assigned range bounds, which is
the interesting-looking part and is a red herring. Varied one axis at a time:

| form | pxx |
| --- | --- |
| `const K = TE(2)`, `TE = (a, b, c)` | **refused** |
| `const K = TRegister($ffffffff)`, explicit `Low(longint)`/`High(longint)` bounds | **refused** |
| `const K = SomeIntAlias($ffffffff)` | accepted |
| `const K = High(SomeOrdinalType)` | accepted |

So it is the **enum target**, not the range, not the literal's width, and not
casting-in-a-const generally.

## Where it was found

`cgbase.pas:401` in the FPC compiler corpus:

```pascal
TRegister = (
  TRegisterLowEnum := Low(longint),
  TRegisterHighEnum := High(longint)
);
...
NR_INVALID = tregister($ffffffff);
```

FPC's own comment says the enum spelling is deliberate — *"TRegister is defined
as an enum to make it incompatible with TSuperRegister to avoid mixing them"* —
so this is idiomatic source someone meant to write, not an edge case.

It became the first failure of those 14 units only on 2026-09-17, when
`efe06a903` accepted `constructor`/`destructor` on an old-style object and let
the parse get 25 lines further down the same file. The `in:` line is what
identifies it: the diagnostic's first line carries no file name, and reading the
line number against the subject unit gives the wrong file every time.

## Log
- 2026-09-17 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
