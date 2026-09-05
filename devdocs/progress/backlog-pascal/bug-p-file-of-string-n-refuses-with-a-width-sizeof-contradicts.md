---
slug: bug-p-file-of-string-n-refuses-with-a-width-sizeof-contradicts
track: P
type: bug
prio: 40
status: backlog
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "`Write(f, s)` to a `file of string[10]` refuses with `the variable is 24 bytes and the file's element type is 11`, and 11 is right — `SizeOf` answers 11 for every spelling of the same variable. FileIOArgSize has a capacity-aware arm for the FROZEN string ABI only, so under the managed default a shortstring falls through to TypeStorageSize and gets the descriptor width. FPC compiles the same program and writes 11 bytes per record. Every other element type blits at exactly SizeOf (measured: Char 1, LongInt 4, packed record 5, record 8), and BlockWrite on the same variable is also correct — so this is one arm, not the file layer."
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
