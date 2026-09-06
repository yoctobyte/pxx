---
slug: bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap
track: P
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: [bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call]
summary: "`procedure(const Fmt: string; Args: array of const) of object` under {$mode objfpc} is refused with `unknown type: const`; fpc 3.2.2 compiles it. Second wall of corpus rung 7 (fcl-passrc) after c4036925a cleared the first. THE PARSE FIX IS THREE LINES AND MUST NOT BE LANDED ALONE -- I wrote it, measured it, and REVERTED it: the procedural-type parameter loop (pasparser_decl.inc ~5157) is the third copy of an arm the free-routine list (pasparser_proc.inc ~940) and the method list (~6609) both have, and adding it makes the declaration parse while the indirect CALL mismarshals, printing Length(Args)=4025888 where fpc prints 3. That converts a clean refusal into a silent wrong number, which is strictly worse. The `[]` row prints 0 CORRECTLY under the broken build -- the empty case collides with the failure value -- so a probe without a non-empty argument list ships the bug. SCOPE IS WIDER THAN THIS TICKET FIRST SAID, corrected 2026-09-06: fpc accepts ALL FOUR spellings -- plain and `of object`, `const`-modified and bare -- under BOTH dialects pxx supports, and pxx refuses all four. The earlier "fpc refuses the plain form too, so pxx refusing it is agreement" was measured in fpc's DEFAULT mode: `-Mfpc` and `-Mtp` give `Type identifier expected`, while `-Mobjfpc` and `-Mdelphi` compile it. Reading the default-mode refusal as the specification shrank the bug to `of object` and marked three real rows as agreement. THAT ROOT-CAUSE READ WAS WRONG AND IS NOW DISPROVEN BY A BUILD: I hypothesised the procedural-type arm sets `mIsArr` but never `LastTypeRecId := TVarRecId` (the element stride `mPTypesRec[i]` reads, which the method arm at ~6869 does set), wrote it, built it, and the declaration parsed while the call still gave Length 0, then 4311000, then a segfault -- the SECOND write-and-revert of this fix. The discriminator was a probe with no `array of const` in it: a plain `array of Integer` literal through the same procedural type fails identically, so the subject is the OPEN-ARRAY LITERAL and not `array of const`. Now blocked-by bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call, which is the real defect and outranks this one because it needs no unusual construct and compiles today in silence."
---

# `array of const` in a method-pointer type

```pascal
{$mode objfpc}
type
  TMsgEvent = procedure(const Fmt: string; Args: array of const) of object;
```

`pascal26:4: error: unknown type: const` — fpc 3.2.2 compiles it. FPC's own
`pscanner.pp` declares an event of this shape, which is how it was found.

## The parser is the easy half and it is a trap

The procedural-type parameter loop at `pasparser_decl.inc` ~5157 does
`Next; Expect(tkOf, 'of'); mTk := ParseTypeKind` with no `tkConst` arm. It is the
**third copy** of an arm the other two parameter lists already have, spelled
identically in both (`TVarRecId`, `mTk := tyRecord`, `LastTypeRecId`):

| list | site | has the arm |
| --- | --- | --- |
| free routine | `pasparser_proc.inc` ~940 | yes |
| method | `pasparser_decl.inc` ~6609 | yes |
| **procedural type** | `pasparser_decl.inc` ~5157 | **no** |

Adding it — three lines, mirroring the others — makes the declaration compile.
**Measured, then reverted:**

```
ev := @L.Emit;  ev('direct', [1, 2, 3]);   fpc: direct n=3   pxx: direct n=4025888
                ev('empty', []);           fpc: empty n=0    pxx: empty n=0
```

So the parse fix trades a clean refusal for a plausible wrong number, and
CLAUDE.md's rule for a construct is to leave the mistake visible. **Do not land
the parser arm without the marshalling.**

**The `[]` row is the reason this needs saying.** It prints `0` correctly under
the broken build, because an empty open array's length collides with the value a
lost length produces. Only a NON-EMPTY argument list discriminates — the same
collision-with-a-legal-value shape as `sizeof(int)` vs unrecorded.

## Scope, measured against the oracle rather than assumed

I had this written up as "procedural types reject `array of const`" before
probing the plain form:

| shape | fpc 3.2.2 | pxx | verdict |
| --- | --- | --- | --- |
| free-routine param | OK | OK | agree |
| method param | OK | OK | agree |
| `procedure(...) of object`, objfpc | OK | **refused** | **the bug** |
| plain `procedure(...)`, no `of object` | refused (`Type identifier expected`) | refused | agree |

The plain procedural type is refused by BOTH. Fixing the loop cannot easily
distinguish them — both forms share it — so an arm placed there accepts the
plain form too. That is us accepting what fpc rejects, which is not a defect,
but it should be a deliberate note in the fix rather than a surprise.

## Where the real work is

The open-array length passed through an INDIRECT call on a procedural type.
`mPArr[i] := mIsArr` is set by the loop, so the parameter is marked as an open
array; what arrives at the callee is wrong. Start from the proc-type call
marshalling, not the declaration.

Reached from [[feature-pascal-corpus-expansion]] rung 7. The first wall of that
rung was `resourcestring` ending a const section, fixed in `c4036925a`.


## 2026-09-06 (frankD) — the blocker is down and this is CLOSER but still not landable

`bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call`
is fixed: the bracket decision is now shared between the direct and indirect
argument loops, so an open-array literal through a procedural type keeps its
length.

With that in, the three-line declaration fix **works on its own terms for the
first time**. Applied on top, the full six-row `array of const` matrix matches
fpc 3.2.2 byte-for-byte — plain procedural type, `of object`, function result,
element `VType` reads, and the empty vector:

```
A plain len=3      B func len=3       C kinds 2 0 1
D method len=3     A plain len=0      F done=1
```

That is the first time this fix has produced a correct number rather than
`Length=4025888`, and it confirms the reason it was reverted twice: it was
never the wrong fix, it was a fix in front of a blocker.

**It still does not land, and the reason is new.** With the declaration fix
applied, `uses pscanner` produces three fresh errors that are not there without
it:

```
pascal26:0: error: incompatible types: cannot assign Integer to record
pascal26:0: error: incompatible types: cannot assign record to Integer
pascal26:0: error: incompatible types: cannot assign Integer to record
```

Revert-controlled: stashing `pasparser_decl.inc` alone, keeping the bracket
fix, removes all three (and brings 575 back). So they are this change's.

**Two hypotheses tested and REFUTED**, recorded so nobody spends the same
half-hour:

- *`LastTypeRecId` leaks into the RETURN type* — `TF = function(const Args:
  array of const): Integer` through an indirect call answers 2 correctly.
- *…or into the FOLLOWING parameter* — `function(const Args: array of const;
  K: Integer): Integer` answers 12 correctly.

The leak, if it is one, needs pscanner's actual shape. `line 0` means no
position was attached, so the next step is to find which declaration produces
it rather than to reason about which could.

**Wall 575 is therefore still open, and it is now the ONLY thing between here
and the next pscanner wall.** After the bracket fix, `uses pscanner` reports
575 and 1994 and nothing else.
