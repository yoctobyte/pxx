---
slug: bug-p-an-enum-typecast-is-not-a-constant-expression
title: "A typecast to an enumerated type is not accepted in a constant expression"
track: P
prio: 45
type: bug
status: open
owner: ""
found-by: frankS
created: 2026-09-17
tags: [constant-expressions, enumerations, typecast, fpc-corpus]
blocked-by: []
summary: "`const K = TE(2);` for `type TE = (a, b, c)` is refused with `not a constant`; fpc compiles it. Three-line repro below. The same cast in an EXPRESSION context works, and so does a cast to an integer alias in a const -- it is specifically the enum target in a constant expression. Found as the FPC corpus's new first failure for 14 of 207 units at cgbase.pas:401, `NR_INVALID = tregister($ffffffff)`, where `tregister` is an enum declared with explicit range bounds (`TRegisterLowEnum := Low(longint), TRegisterHighEnum := High(longint)`) so that it is incompatible with `tsuperregister` -- an idiom fpc's own compiler uses deliberately. The explicit range is NOT the cause: a plain three-member enum reproduces it. Wired to umbrella-pxx-compiles-fpc-itself; do NOT rank it on the 14, which is a queue position and not a count of work -- that umbrella has recorded sixteen consecutive null rows saying so."
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
