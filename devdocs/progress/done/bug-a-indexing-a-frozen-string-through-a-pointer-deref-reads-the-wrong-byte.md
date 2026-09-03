---
prio: 55
track: A
type: bug
status: done
summary: "RESOLVED `0dd5858e6`. AND IT WROTE THE WRONG BYTE AS WELL AS READING ONE -- the slug undersells it as a display bug. With the fix reverted and rebuilt, `p^[1] := 'H'` stores at base+8 too: inside the slot, corrupting nothing visible, and the assignment is SILENTLY DISCARDED (the program prints `read [NUL NUL NUL]` and then `write [hello]`). Silent corruption, not a wrong character. The write half was found by the POSITIVE CONTROL, not by the repro -- reverting to prove the fix is what showed it. Cause: `IRLowerAddress` derives the index origin from the prefix width (`lo := -(FrozenStrPrefixSize(tk) - 1)`) and took `tk` from the base node's own ASTTk, which on a deref is the generic tyString = an 8-byte prefix. The pointee's kind was never missing: it is PtrElemTk on the pointer's own symbol. Verified 10/10 vs the FPC oracle. `p^[1]` for `p: ^string[10]` reads a BLANK on all four converted backends under -dPXX_SHORTSTRING at 764dc3a30, where `s[1]` and `r.f[1]` both read 'h' in the same run. So the index ORIGIN is right in general and wrong specifically through a deref -- the chars start at base+prefix and this path is still adding the wide offset. Survives the four-cause fix; caught by test_shortstring_through_a_pointer's `index deref` row."
---

# Indexing a frozen string through a pointer deref reads the wrong byte

```pascal
type TS10 = string[10]; PS = ^TS10;
var s: TS10; p: PS;
begin
  s := 'hello'; p := @s;
  WriteLn(s[1]);    { h  — correct }
  WriteLn(p^[1]);   { blank }
end.
```

Measured 2026-09-02 at `764dc3a30`, compiler `e81a80c4621c`, under
`-dPXX_SHORTSTRING`, on **x86-64, aarch64, arm32 and riscv32**. Default mode is
correct on all four.

## Why it is the deref path and not the index origin

`index direct` (`s[1]`) and `index field` (`r.f[1]`) are **green in the same
run on all four backends**. Only the deref spelling is wrong. So the origin
computation follows the prefix width correctly where the symbol is reachable,
and does not where the operand is a bare pointer whose value IS the buffer
address — the same shape that made `Length(p^)` wrong before `764dc3a30`.

A blank rather than garbage is consistent with reading at `base + 8` while the
chars begin at `base + 1`: offset 8 of an 11-byte slot holding `'hello'` is
still inside the slot and still zero-filled.

## Where it is asserted

`test/test_shortstring_through_a_pointer.pas`, row `index deref`. One of the
two reasons that file's `-dPXX_SHORTSTRING` rows are not yet wired.

[[bug-a-comparing-a-frozen-record-field-to-a-literal-crashes-or-answers-false]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

## RESOLVED — 0dd5858e6

Cause: DerefFrozenStrPtrSym wired into IRLowerAddress; closed the silently DROPPED WRITE with the read.

Re-verified at 05f50f9ae with the repro in this ticket, unchanged, against the
FPC 3.2.2 oracle: exact match at default AND -dPXX_SHORTSTRING. Covered going
forward by test/test_frozen_field_and_deref_readers.pas, wired into all 12
expected blocks (4 native modes; x86-64, aarch64, arm32, riscv32, xtensa x 2
modes) — the 32-bit targets included, since this is a width class and x86-64 is
where width bugs hide.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
