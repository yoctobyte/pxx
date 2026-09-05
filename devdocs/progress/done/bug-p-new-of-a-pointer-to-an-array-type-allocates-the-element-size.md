---
slug: bug-p-new-of-a-pointer-to-an-array-type-allocates-the-element-size
title: "`New(p)` for a pointer to an array type allocates ONE ELEMENT, so every write past the first block overruns the heap"
track: P
prio: 70
type: bug
status: done
owner: "frankB"
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "FIXED in the same commit that files this. `New(p)` sized the block with TypeSlotSize(Syms[idx].PtrElemTk) — the pointee's ELEMENT kind — so `P1D = ^array[0..17] of Char` allocated one byte, the allocator rounded it to 16, and writing the array ran 2 bytes into the next block. Silent, exit 0, no diagnostic; the corruption surfaces as some other pointee's bytes changing. Measured against fpc: allocator gap 16/16/32 for a 1-D array, a 2-D array and a record pointee against fpc's 32/32/32 — the RECORD arm was already right (RecSize answered for it), which is why nothing caught this. Both New spellings shared the defect. Fixed by ArrTypeByteSize (symtab.inc), which is SizeOf's own named-array rule lifted out of pasparser_expr.inc so all three callers ask one question."
---

# The measurement

```pascal
type T1D = array[0..17] of Char; P1D = ^T1D;
var a, b: P1D; i: Integer;
begin
  New(a); New(b);
  for i := 0 to 17 do b^[i] := '#';
  for i := 0 to 17 do a^[i] := Chr(Ord('a') + i);
  for i := 0 to 17 do write(b^[i]);   { pxx: qr################   fpc: ################## }
end.
```

Filling `a^` overwrote the first two characters of `b^`. Consecutive-`New` gaps,
pxx against fpc:

```
SizeOf(T1D)=18  gap 1-D    = 16     fpc: 32
SizeOf(T2D)=18  gap 2-D    = 16     fpc: 32
SizeOf(TRc)=18  gap record = 32     fpc: 32
```

`SizeOf` was right the whole time. Only the allocation was wrong, and only for
the array pointee.

# Why it survived

**The one arm that worked is the one everybody writes.** `New` over a
`^TRecord` is the idiomatic use, and `TypeStorageSize`/`RecSize` answer for it
correctly, so the intrinsic looks exercised. `^TArray` takes the other arm of
the same conditional, and there `PtrElemTk` is the ELEMENT's kind — the value
the INDEX path wants, reused by the sizing path where it means something else.

The name is not the thing: `PtrElemTk` means "the kind you get when you deref
and index", and the size question needed "the size of what `p^` is".

# The fix

`ArrTypeByteSize(ai)` in `symtab.inc`, beside `TypeStorageSize`. It is the tail
of `SizeOf(TArrayTypeName)` moved out of `pasparser_expr.inc`, unchanged —
dynamic pointee answers the handle width, multi-dim flattens the dim spans,
record elements go through `RecSize`. Three callers now:

- `SizeOf(TNamedArray)` — `pasparser_expr.inc`, the original, so the helper
  arrives with the existing tests behind it
- `New(p)` statement form — `pasparser_stmt.inc`, keyed on `SymPtrElemArrAi`
- `New(PType)` function form — `pasparser_expr.inc`, keyed on
  `AliasPtrElemArrAi`

The function form's own source comment already said *"if the size rule ever
changes it changes in both arms or neither"*. It had not; this is that.

# What it was misfiled as

[[bug-p-a-char-array-row-through-a-pointer-deref-loads-short]] — filed a day
earlier with a diagnosis pointing at the dimension table. Row 1 of a corrupt
pointee reads `103 104 32 0 0 0`, and three characters plus a terminator is
indistinguishable from a reader that stops early. That ticket's own advice was
*"do not fix this by widening `ASTCharArrayCap`"*, and widening it is exactly
what was correct once the bytes were there. See its RESOLVED section.

# Tests

- `test/test_new_of_a_pointer_to_an_array_type.{pas,expected}` — five rows, fpc
  oracle. Asserts the OBSERVABLE (a second pointee reads back what was written
  to it) rather than allocator gaps, which are an implementation detail this
  file does not claim fpc's. Row 3 is the record pointee, green before the fix,
  present to record why nothing caught this. Row 4 is the function spelling.
- `test/test_char_array_nd_row_is_a_string.{pas,expected}` gained the two deref
  rows it had documented an ABSENCE for, heap and stack.
- `test/test_char_array_3d_row_through_a_deref_not_a_string_fail.pas` — the
  sibling negative control: admitting the deref base to `ASTCharArrayCap`
  widened the 3-D subscript-count guard to a base nothing exercised it on.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
