---
slug: bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap
track: P
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "`procedure(const Fmt: string; Args: array of const) of object` under {$mode objfpc} is refused with `unknown type: const`; fpc 3.2.2 compiles it. Second wall of corpus rung 7 (fcl-passrc) after c4036925a cleared the first. THE PARSE FIX IS THREE LINES AND MUST NOT BE LANDED ALONE -- I wrote it, measured it, and REVERTED it: the procedural-type parameter loop (pasparser_decl.inc ~5157) is the third copy of an arm the free-routine list (pasparser_proc.inc ~940) and the method list (~6609) both have, and adding it makes the declaration parse while the indirect CALL mismarshals, printing Length(Args)=4025888 where fpc prints 3. That converts a clean refusal into a silent wrong number, which is strictly worse. The `[]` row prints 0 CORRECTLY under the broken build -- the empty case collides with the failure value -- so a probe without a non-empty argument list ships the bug. SCOPE IS WIDER THAN THIS TICKET FIRST SAID, corrected 2026-09-06: fpc accepts ALL FOUR spellings -- plain and `of object`, `const`-modified and bare -- under BOTH dialects pxx supports, and pxx refuses all four. The earlier "fpc refuses the plain form too, so pxx refusing it is agreement" was measured in fpc's DEFAULT mode: `-Mfpc` and `-Mtp` give `Type identifier expected`, while `-Mobjfpc` and `-Mdelphi` compile it. Reading the default-mode refusal as the specification shrank the bug to `of object` and marked three real rows as agreement. ROOT CAUSE, read 2026-09-06 and not yet proven by a build: the procedural-type arm sets `mIsArr` but never `LastTypeRecId := TVarRecId`, which is what `mPTypesRec[i]` reads for the ELEMENT STRIDE -- the method arm at ~6869 sets both. If that is it, the work is in the parser after all and not in the marshalling path this summary previously named."
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
