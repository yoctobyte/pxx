---
slug: bug-p-sizeof-string-disagrees-with-the-storage-string-actually-gets
track: P
type: bug
prio: 55
status: done
found: 2026-08-31
found-by: frank-rust
owner: frank-rust
blocked-by: []
summary: "`SizeOf(string)` answered a hardcoded 8 on i386, arm32 and riscv32, where a `string` variable, record field and array element every one of them occupied 4 -- so pxx disagreed with ITSELF inside a single program (`SizeOf(string)` = 8, `SizeOf(v)` = 4 for `v: string`). Only the bare TYPE NAME was wrong; every value, stride and layout was already right. Cause: BuiltinTypeNameTk (the table SizeOf consults) hard-wired `tyString` while the declaration path asked BareStringKind, which answers tyAnsiString in the default managed build -- the identical shape as bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets, whose fix is the arm five lines above and which was never grepped for its siblings."
---

# `SizeOf(string)` disagrees with the storage a `string` actually gets

## Repro

```pascal
program sinc;
type TA4 = array[0..3] of string;  TRS = record s: string; end;
var v: string; a: TA4; p, q: ^string;
begin
  WriteLn(SizeOf(string));            { the TYPE     -> 8   WRONG }
  WriteLn(SizeOf(v));                 { a VARIABLE   -> 4   right }
  WriteLn(SizeOf(TA4) div 4);         { array stride -> 4   right }
  WriteLn(SizeOf(TRS));               { record field -> 4   right }
  WriteLn(SizeOf(Pointer));           {              -> 4         }
  p := @a[0]; q := @a[1];
  WriteLn(PtrUInt(q) - PtrUInt(p));   { addr stride  -> 4   right }
end.
```

`pascal26 --target=riscv32` (also i386, arm32) printed `8 4 4 4 4 4`. x86-64 and
aarch64 printed `8` throughout and were correct by coincidence — the hardcode
happens to equal the pointer width there, which is why this survived.

## Why it matters

`GetMem(SizeOf(string) * n)` merely over-allocates. `Move(src, dst,
SizeOf(string))` copies **8 bytes out of a 4-byte slot** — it reads and writes a
neighbouring field. Silent, and only on the targets where it is least likely to
be noticed. That is verbatim the consequence recorded in the `Real` ticket below.

## Cause

Two paths answer "what is a bare `string`", and only one of them asked:

- **Declaration** (`var v: string`) → `ParseTypeKind` → `BareStringKind`, which
  consults `PXX_MANAGED_STRING` and gives `tyAnsiString` in the default build.
  `TypeSize(tyAnsiString)` is already `TARGET_PTR_SIZE` — correct.
- **`SizeOf`** → `BuiltinTypeNameTk` (`pasparser_lval.inc`) → the arm
  `else if CaseEqual(nm, 'string') then Result := tyString`. `TypeSize(tyString)`
  is a literal `8` (`symtab.inc:2983`, kind 4).

`BuiltinTypeNameTk`'s own header says *"One table, so the next builtin type
cannot be present in half the compiler"*, and the arm **immediately below** it
(`ansistring`/`unicodestring`/`widestring`) already consults the define. The one
entry that still disagreed was the one the function was written to fix.

**This is the sibling of `bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets`**,
whose fix — `Result := RealTypeKind` — is five lines above in the same chain,
and whose comment describes this bug word for word with `Real` in place of
`string`. CLAUDE.md's rule is *if you fix a bug on one arm of a double case,
grep for the sibling before closing the ticket*; that grep was not done, so the
`string` arm sat there while the `Real` arm's comment explained exactly what was
wrong with it.

## Fix

`BareStringKind` moved from `pasparser_decl.inc` to `util.inc`, beside
`RealTypeKind` — the sibling one-answer helper, upstream of every caller — and
the `string` arm now calls it. Three sites were separately short-circuiting
`'string'` before reaching this table (RTTI in `pasparser_expr.inc`, operator
overloading in `pasparser_call.inc`, plus the declaration path): two mechanisms
is a smell and three is a design flaw. The two remaining short-circuits are
**deliberately kept**, and both are genuinely different questions rather than
copies:

- RTTI must report `tyAnsiString` regardless of build, because it reports the
  string MODEL the program observes, not the internal tag.
- Operator overloading is unconditional by long-standing intent.

## Verified — fixedpoint `bab147eec504`

- `SizeOf(string)` now equals the variable, the array stride, the record field,
  the address delta and `SizeOf(Pointer)` on **all five** targets measured:
  native, riscv32, i386, arm32, aarch64.
- **The self-host fixedpoint proves nothing here and must not be cited.**
  `compiler.pas` builds with `-uPXX_MANAGED_STRING`, where `BareStringKind` *is*
  `tyString` — so the gate cannot see this change at all. This is CLAUDE.md's
  language-surface limit, and the probes above are the evidence instead.
- The table's two other live callers were exercised because a changed type tag
  reaches them too: the `string(x)` typecast (from `Char` and from `PChar`) and a
  `type helper for string` receiver, on a variable and on a literal — all
  correct, and **byte-identical to the pinned compiler** on x86-64.
- FPC 3.2.2 oracle (x86-64, `{$MODE OBJFPC}{$H+}`) agrees: `SizeOf(string)` =
  `SizeOf(Pointer)` = 8. No i386 FPC is installed here, so the 32-bit half is
  pxx's own internal consistency, which is the stronger claim anyway — the
  compiler was contradicting itself within one program.

## Log
- 2026-08-31 — resolved, commit e42c4518d.
