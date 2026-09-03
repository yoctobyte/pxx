---
track: A
prio: 60
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "FIXED. x86-64's `String = Char` / `Char = String` arms guarded on `lhsTk = tyString` — a test for the GENERIC frozen tag, not for membership. A variable's IR_LEA carries that legacy tag so `s = 'X'` matched; an array ELEMENT and a record FIELD are tagged with their real frozen kind and fell through to EmitStrCmpReg, which dereferences the Char's ORDINAL as a string address. `a[0] = 'X'` for `a: array[0..1] of string[8]` SIGSEGVs on the PINNED compiler in DEFAULT mode — this ships today and is not a flip defect. The same arms also read the length as an 8-byte word, which under -dPXX_SHORTSTRING made every such comparison answer 'not equal' in both directions."
---

# Char vs a frozen string matched only the one shape that carries the legacy tag

Found 2026-09-04 (frankb-78, Track A) while closing the last of the four
phase-4 shortstring-flip defects. **Two defects in one pair of arms**, and only
one of them was about the flip.

## The crash predates the flip and ships today

```pascal
var a: array[0..1] of string[8];
begin a[0] := 'X'; WriteLn(a[0] = 'X'); end.
```

SIGSEGV — measured on `stable_linux_amd64/default/pinned`, **default mode, no
flag**. A record field is the same shape and crashes identically.

The guard was `lhsTk = tyString`. That is a test for the tag the IR puts on a
frozen string *generically*, not a test for "is this a frozen string". A plain
variable lowers to `IR_LEA`, which carries the legacy `tyString`, so `s = 'X'`
matched and was correct. An array element and a record field are tagged with
their **real** kind (`tyFixedString` / `tyShortString`), so neither arm claimed
them and the comparison fell through to `EmitStrCmpReg` — which expects two
string addresses and was handed the Char's **ordinal**.

`TypeIsFrozenString(lhsTk)` is the membership test the arms wanted, and
`IRStrTkOf` is the accessor. Both were already in the file; the sibling concat
arm three hundred lines away had been converted to them and this pair had not.

## What the flip added

The same arms read the length with `mov rcx, [rax]` and the character at
`[rax+8]`. Under a byte prefix the first eight bytes are the length byte
followed by seven characters, so `cmp rcx, 1` never matched and every Char/String
comparison took the not-equal arm — **in both directions**. Fixed at
`b97167982`; this ticket is the shape half of the same pair.

## Why it survived a test named for it

`test_char_string_equality_both_directions` asserts that the two DIRECTIONS
AGREE. They agreed — wrongly — on every row: `('a' = s) = (s = 'a')` is True
when both are False. Only its second column, printing `'a' = s` alone, could
see it, and the array-element shape it never tried at all.

## The test

`test/test_frozen_string_char_compare_shapes.pas` — five lvalue shapes
(variable, `shortstring`, record field, array element, pointer deref) × both
directions × literal and variable Char, plus a negative half and a
length-2 half so a guard that only ever says TRUE cannot pass. Every row is a
RELATION, so the file carries no per-target width and means the same thing in
both prefix modes on all seven backends. `.expected` is FPC 3.2.2's output.
Wired for x86-64, aarch64, arm32 and riscv32, both modes. **The pinned
compiler's crash on the `elem` row is its positive control.**
