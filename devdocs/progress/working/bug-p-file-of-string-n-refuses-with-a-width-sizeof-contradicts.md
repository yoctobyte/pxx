---
slug: bug-p-file-of-string-n-refuses-with-a-width-sizeof-contradicts
track: P
type: bug
prio: 40
status: working
found: 2026-09-05
found-by: frankD
owner: frankB
blocked-by: []
summary: "`Write(f, s)` to a `file of string[10]` refused with `the variable is 24 bytes and the file's element type is 11`, and 11 is right. FIXED. The filed cause was wrong and the correction is the finding: nothing ever fell through to TypeStorageSize and 24 is not a descriptor width. `FileIOArgSize` reached the capacity-aware sizer every time -- it called `SizeOfSlot(tk, cap)` with the CAPACITY read off the symbol and the KIND read off the AST node, and an ident node for a frozen string carries the legacy overloaded `tyString` whatever the symbol is (measured with a PXXDBG probe: `nodeTk=4 symTk=25 symCap=10`). tyString's length prefix is eight bytes, so a shortstring was sized 10+8 rounded to 24. TWO ARGUMENTS TO ONE SIZER, DESCRIBING ONE VARIABLE, OUT OF TWO RECORDS -- and of the twelve `SizeOfSlot` call sites this was the only one whose kind and capacity came from different records. THE BUG IS INVISIBLE ABOVE 255: `string[N]` is tyShortString up to 255 and tyFixedString above it, and tyFixedString's prefix is also eight, so the wrong kind is right by coincidence there -- `file of string[300]` always compiled while `file of string[10]` never did. This is the LAYOUT half of the frozen-string question and no size assertion can see it; the test asserts the ON-DISK BYTE COUNT, because FileSize counts records and every copying path normalises the prefix."
---

# `file of string[N]` refuses, with a width `SizeOf` contradicts

Measured at HEAD `ce19e5482`, binary `9bcfd2b4da30`:

```pascal
program f2;
var f: file of string[10]; t: string[10];
begin
  Assign(f,'o2.bin'); Rewrite(f); t := 'hi'; Write(f,t); Write(f,t); Close(f);
end.
```

```
pascal26:4: error: read/write(file): the variable is 24 bytes and the file's
element type is 11
```

**The 11 is correct and the 24 is not.** `SizeOf` answers 11 for the type, for a
variable of an alias of it, and for an inline `string[10]` var, and an
`array[0..1] of string[10]` strides by 11. FPC 3.2.2 compiles the same source
and the file is 22 bytes for two records — 11 each, agreeing with our own
`SizeOf`.

## Where it is

`FileIOArgSize`, `compiler/pasparser_stmt.inc:3517`:

```pascal
  if TypeIsFrozenString(tk) then
  begin
    if ASTKind[node] = AN_IDENT then Result := SizeOfSlot(tk, SymStrCap[ASTIVal[node]]);
  end
  else
    Result := TypeStorageSize(tk, ResolveNodeRec(node));
```

The capacity-aware branch is reached only for the **frozen** string ABI. Under
the managed default a `string[N]` is not a frozen string, so it takes the `else`
and `TypeStorageSize` returns the descriptor width rather than `N+1`. The
`SymStrCap` lookup the correct answer needs is already right there.

The declared-side width (`declSz`, from `SymFileRecSize`) is computed elsewhere
and is right, which is why the diagnostic prints the two numbers side by side
and reads like a real mismatch.

## What is NOT broken — the scope this bounds

Same session, same binary, all correct and all writing exactly `SizeOf` per
record: `file of Char` (1), `file of LongInt` (4), `file of packed record
Byte;LongInt` (5), `file of record Byte;LongInt` (8). `BlockWrite(f, s,
SizeOf(s))` on an untyped file writes 11 for a `string[10]` and 312 for a
`string[300]`, both matching `SizeOf`. So the record file layer, the size
computation for records, and the blit path are all fine; this is the one arm.

## Why it matters beyond the one program

A record file of fixed-width strings is the classic Turbo/Delphi flat-file
idiom, and `string[N]` is the type that exists for it — the whole reason to
choose a fixed string over a managed one is that it has a width you can put on
disk. Refusing it removes the use case.

Found while writing the representation contract
([[feature-d-a-representation-contract-because-there-is-no-spec-to-appeal-to]]),
which has a "what `file of T` can blit" section. That section will document the
refusal as current behaviour and should be revisited when this lands.


## Resolved 2026-09-06 — frankB, in Group 19 ("how many bytes is this type", asked through a door that never reaches the capacity table)

**The filed cause was wrong, and correcting it is most of the value.** The ticket
said the frozen arm was taken only under the frozen-string ABI and that a
managed-default shortstring fell through to `TypeStorageSize` and got a
descriptor width. It never fell through. `TypeIsFrozenString(tyString)` is TRUE,
so the frozen arm ran on every one of these, reached `SizeOfSlot`, and got the
capacity right.

What was wrong was the OTHER argument.

```
  FileIOArgSize:  SizeOfSlot( IntToTypeKind(ASTTk[node]),   SymStrCap[ASTIVal[node]] )
                              ^-- from the NODE                ^-- from the SYMBOL
```

Measured, not inferred — a temporary `PXXDBG p.fiosize` probe printed
`nodeTk=4 symTk=25 symCap=10 -> 24` for `t: string[10]`. Kind 4 is the legacy
overloaded `tyString`; kind 25 is `tyShortString`, which the declaration
actually produced. `FrozenStrPrefixSize` is 8 for the first and 1 for the
second, so the sizer was asked about a variable that does not exist.

### The tell, and why the ticket sat

`ParseTypeKind` makes `string[N]` a `tyShortString` for N <= 255 and a
`tyFixedString` above it, and `tyFixedString`'s prefix is eight bytes — the same
as `tyString`'s. **So the wrong kind gives the right answer above 255.**
Measured across the boundary at one tree:

| declaration | nodeTk | symTk | sizer said | element | outcome |
| --- | --- | --- | --- | --- | --- |
| `string[10]` | 4 | 25 | 24 | 11 | REFUSED |
| `string[255]` | 4 | 25 | 264 | 256 | REFUSED |
| `string[256]` | 4 | 26 | 264 | 264 | compiles |
| `string[300]` | 4 | 26 | 312 | 312 | compiles |

`file of string[300]` has always worked. Anyone reaching for the big case first
finds a working feature, and the failing case looks like a small-string quirk
rather than a kind that was never consulted.

### Why a size test could not have caught it

frankH's measurement on `6a890a405` is the general form and it applies exactly
here: **every path that COPIES a shortstring normalises the prefix** —
assignment, value parameter, `Length`, `WriteLn` — so values and record counts
agree under both layouts, and a values-and-`FileSize` test passes with the bug
present. `FileSize` on a typed handle counts RECORDS, so it answers 2 either
way. The test therefore reopens the same file as `file of Byte` and asserts 22.
That row is the only one in the file that can fail.

### The fix

One site. Take the kind from the same record the capacity comes from, guarded so
the arm's population is unchanged (a symbol that is not itself a frozen string
is not moved). `pasparser_stmt.inc`, `FileIOArgSize`.

### Verified

- `fpc -Mobjfpc` on the identical program: same values, same record count, and
  the written file is **byte-identical** to ours at 22 bytes.
- Positive control `-dROW_MISMATCH`: a genuine 256-vs-11 disagreement is still
  refused — and now says 256 rather than 264, so the same wrong field had been
  making the diagnostic wrong as well as the decision.
- `make compiler/pascal26`: `converged after 1 round(s)`.
