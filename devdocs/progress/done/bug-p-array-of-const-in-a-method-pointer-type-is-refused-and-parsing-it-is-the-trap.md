---
slug: bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap
track: P
prio: 45
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "DONE 2026-09-06 (87681a64a). `procedure(const Fmt: string; Args: array of const) of object` compiles and marshals correctly, in all four spellings -- plain and `of object`, `const`-modified and bare -- byte-identical to fpc 3.2.2 under -Mobjfpc. The fix was an EXTRACTION, not the fourth copy: `array of const` was parsed by three parameter lists and implemented by two, the free-routine list (pasparser_proc.inc) and the method list (pasparser_decl.inc ~7155) carrying the same eight lines character for character while the procedural-type list carried nothing; all three now call ParseArrayOfConstElem. The two earlier write-and-reverts were correct to revert: the declaration parsing only exposed the open-array literal losing its length through a procedural-type call, and that blocker (fe0c492d1) was the real prerequisite. Wall 575 of corpus rung 7 cleared; the rung then went 893 -> 2899 through two further fixes that had nothing to do with array of const.""
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

### Where the `line 0` errors come from — the emitter, at least

`ir.inc:11660`, the AN_ASSIGN type check:

```pascal
  if AssignSideKind(ASTLeft[node], asgDstTk) and
     AssignSideKind(ASTRight[node], asgSrcTk) and
     AssignKindsIncompatible(asgDstTk, asgSrcTk) and
     not AssignHasConversionOperator(ASTRight[node], ASTLeft[node]) then
    ErrorAtRecover(ASTLine[node], 'incompatible types: cannot assign ' + ...);
```

So it is a real assignment being rejected, in IR rather than in the parser, and
`0` is `ASTLine[node]` — **the AN_ASSIGN node was built with no line recorded.**
Two consequences worth separating:

1. For this ticket: something in pscanner is assigning between an Integer and a
   record once the `array of const` parameter exists. The check is
   recovering rather than fatal, which is why three appear rather than one.
2. Independently of this ticket: a diagnostic that can only ever print `0` is
   the third position bug found today, after frankS's parked diagnostic that
   carries a line but no FILE and frankB's line/`near:`-window desync. Three
   different mechanisms, one reader-visible symptom — a real-looking position
   that points nowhere or somewhere wrong. Worth one write-up rather than three.

Next step is to find WHICH assignment, not to reason about which could be:
`ASTLine` being 0 means the usual bisect-by-line does not work, so bisect
pscanner by chopping the unit instead.

## 2026-09-06 — independently re-measured after closing (frankB, Group 21)

Re-measured at `1d9d36ff3` **without reading this ticket** — I had it on a stale
`ready --track P` listing as still open and went to measure rather than re-read,
which is the only reason the confirmation is worth anything.

All four spellings (plain / `of object`, `const`-modified / bare) across four
dialects, and both call shapes with a non-empty argument list:

```
pxx:  bare F=direct Length=3 | bare F=indirect Length=3 | of object F=method Length=3 | empty 0 | empty 0
fpc:  bare F=direct Length=3 | bare F=indirect Length=3 | of object F=method Length=3 | empty 0 | empty 0
```

Byte-identical, including the non-empty lists this ticket warned about — the
`[]` row prints 0 correctly under the broken build, so only a non-empty list
separates a fix from the failure value. `-Mfpc` and `-Mtp` accept the
declaration where fpc 3.2.2 refuses it, which is us accepting what FPC rejects
and not a defect.

**Recorded because reading `done/` would have been the same source.** A second
reading only counts if it can fail differently, and a folder listing cannot fail
differently from the fix that put the file there.
