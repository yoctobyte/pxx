---
prio: 60
track: A
type: bug
status: done
summary: "SizeOf(string[N]) was prefix+N and NOT rounded up to the prefix's alignment, so it was an illegal ARRAY STRIDE: element 1 of `array of string[10]` began 2 mod 4 and xtensa bus-errored on the 8-byte prefix -- on the STORE and on Length() -- in the default mode, both ABIs, at the pin. Fixed by padding the slot, so stride = SizeOf again. The sweep for fallout found three more, all -dPXX_SHORTSTRING and all silent: two `string[10]` record fields OVERLAPPED, a truncating store into a `string[4]` FIELD wrote past it into its neighbour, and `a[0][1]` read an 8-byte prefix. Layout now byte-identical to FPC 3.2.2 under the flag."
owner: frankB
---

# Storing into an element of an array of frozen strings bus-errors on xtensa

```pascal
program xt;
type TS10 = string[10];
var arr: array[0..2] of TS10;
begin
  WriteLn('size ', SizeOf(TS10), ' stride ', PtrUInt(@arr[1]) - PtrUInt(@arr[0]));
  arr[0] := 'zero';  WriteLn('elem0 ok <', arr[0], '>');
  arr[2] := 'two';   WriteLn('elem2 ok <', arr[2], '>');
  arr[1] := 'one';   WriteLn('elem1 ok <', arr[1], '>');
end.
```

```
$ pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh xt.pas xt
size 18 stride 18
elem0 ok <zero>
elem2 ok <two>
qemu: uncaught target signal 7 (Bus error) - core dumped
```

Measured 2026-09-03. **Reproduces on the PINNED compiler (v401) byte for byte**,
so it predates the byte-prefix work entirely and is not a regression from it.

## What the three rows establish, and why they are all in the repro

`arr[0]` is at offset 0 and `arr[2]` at 36 — both 4-aligned, both correct.
`arr[1]` is at offset 18, which is 2 mod 4, and it is the only one that traps.
The element stride IS `SizeOf(TS10)` = 18 in the default mode (8-byte
`NativeInt` prefix + 10 chars, no padding), so **every odd element of any
`array of string[N]` whose size is 2 mod 4 is misaligned**, and the store of the
8-byte length prefix is what xtensa refuses. A repro with only `arr[1]` in it
would look like "array element stores are broken on xtensa"; the aligned pair is
what makes it an ALIGNMENT finding rather than a codegen-shape one.

Consistent with that:

| | |
| --- | --- |
| `-dPXX_SHORTSTRING` (1-byte prefix, `SizeOf` = 11) | **correct** — no wide store, nothing to misalign |
| both xtensa ABIs (windowed default, `--xtensa-abi=call0`) | identical crash |
| x86-64, i386, arm32, aarch64, riscv32 | correct — they permit the unaligned store, or the backend splits it |
| a record field (`r.f := 'hello'`) and a plain variable | correct — the allocator gives those an aligned slot |

Two plausible fixes and they are not equivalent: **align the type** (pad
`string[N]` to a multiple of 4 in the default mode on targets that require it,
which changes `SizeOf` and therefore layout) or **split the store** (emit the
prefix write as two aligned halves on xtensa, which is local to the backend and
changes no layout). The second is the smaller change; the first is the one that
also fixes every OTHER wide access to a misaligned element, and nothing has
established that the prefix store is the only one.

## How it was found

It is why `test/test_shortstring_through_a_pointer.pas` is wired on xtensa under
the flag ONLY: in the default mode that file dies at its third statement,
`arr[1] := 'hello'`, before printing a line. The Makefile comment there cites
this ticket, so the next reader does not conclude that the byte prefix is the
reason a row is flag-only. Restore the xtensa default row when this lands.

[[bug-a-setlength-on-a-frozen-string-is-unsupported-on-riscv32]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]


## RESOLVED (frankB, 2026-09-03) — one crash, and three silent ones the sweep for it found

### The crash: a size that was not a legal stride

`FrozenStrSlotSize` answered `cap + prefix` and nothing rounded it up. That size
is ALSO the array stride, and the prefix is a wide scalar, so
`array[0..3] of string[10]` strode 18 bytes: element 1 began 2 mod 4 and the
8-byte length word was unaligned. Xtensa traps it -- and not only on the store
this ticket reported. **`Length(arr[1])` traps identically**, which rules out the
"split the store in the backend" option listed second above: the READ is the
same access.

The record path had already reached the right answer by a different route (it
aligns each FIELD start to `TARGET_PTR_SIZE` and pads), which is the
two-mechanisms-for-one-concept smell -- `SizeOf` said 18 while the field layout
behaved as if 24, and only an array could tell them apart. Rounding the slot up
in `FrozenStrSlotSize` makes **stride = SizeOf** again, the rule every Pascal
program may assume and FPC guarantees, and both mechanisms now agree by
construction. New `FrozenStrAlign` is the single fact both consumers ask.

`tyShortString` is excluded and must stay excluded: a byte prefix over byte
content needs no alignment, and padding it would break the FPC ABI the flag
exists to reproduce.

**The alignment is the prefix width CAPPED AT A MACHINE WORD**, not the prefix
width. The first draft of the regression test asserted `stride mod 8` and passed
on x86-64 and aarch64 while failing on i386, arm32, riscv32, wasm32 and xtensa:
the 8-byte prefix is two words on a 32-bit target, so 4-alignment is what it
needs and what it gets.

### The three the sweep found, all silent, all -dPXX_SHORTSTRING

1. **Two frozen fields OVERLAPPED.** `record x, y: string[10]` measured 16 bytes
   with y at offset 8 (FPC: 22 and 11), so writing y truncated x to seven
   characters. The field-size test named `tyFixedString` only, so the flag's kind
   fell through to `TypeSlotSize` -- a POINTER WIDTH for a string. Same
   enumeration in the class-field path; the variant-part path a few hundred lines
   up already tested both kinds.
2. **A truncating store into a FIELD ran past it.** `r.f := 'abcdefgh'` into a
   `string[4]` field wrote all eight bytes, into the neighbouring field. The
   clamp asked `lhsStoreTk = tyString`, which covered `tyFixedString` only
   because a fixed-string field is RECORDED as tyString. The VARIABLE and ARRAY
   ELEMENT spellings of the same assignment truncate correctly in both modes, so
   only the field spelling could show it.
3. **`a[0][1]` read the wrong prefix.** An array-element base fell to
   `IntToTypeKind(ASTTk[baseNode])`, the generic tyString, so the character index
   origin came out `base+8` where the first character is at `base+1`: a blank
   instead of 'h', and `@a[0][1]` seven bytes past the character it names. The
   variable, field and pointer-deref spellings were all correct -- the deref one
   because it had been fixed here before, one arm over. `ASTFrozenArgTk` is the
   existing "ask the ENTITY, not the node" answer and already had the array arm.

All four are one shape: **a fact about a frozen string asked of something that
stopped answering for it**, and in three of the four the entity that does know
was already being asked one arm away.

### Verification

- `test/test_frozen_string_layout.pas` -- 23 relations, no number in the compared
  output, so ONE .expected serves both modes AND **FPC 3.2.2, which compiles and
  runs the file unmodified and prints the same lines**.
- 7 targets x 2 modes, xtensa both ABIs: 16/16 MATCH.
- Positive control: compiler changes stashed and rebuilt -- native fails the
  alignment rows in both modes and the overlap / truncation / char-index rows
  under the flag, and **xtensa bus-errors**; restored (`5e4b945cf5bb`) -- MATCH.
- `gate.sh quick` GREEN with `compiler/**` uncommitted, so the FPC seed canary
  ran rather than printing SKIP.
- Fallout sweep over every test source naming both `string[` and `SizeOf`
  (11 files, both modes, the layout-sensitive ones on all seven targets). Two
  rows moved and **both were assumptions rather than measurements**:
  `test_shortstring_byte_prefix` printed `SizeOf` (18/11) and now prints the
  PREFIX (`@s[1] - @s`, 8/1) -- one expected string for every target instead of
  seven hardcoded copies, and a stronger control; and
  `test_sizeof_stringn_matches_storage` bracketed the slot at `<= 18`, now
  `<= 8 + 10 + SizeOf(Pointer) - 1`, still derived from the declaration and
  still rejecting the 263/264 defaults. `test_shortstring_through_a_pointer`
  derived its prefix as `SizeOf - 10` and now asks `@d[1]`, which is where the
  LANGUAGE says the first character is and survives any future padding.
- **The xtensa DEFAULT row of `test_shortstring_through_a_pointer` is restored**
  (it was flag-only because of this crash), and the Makefile comment citing this
  ticket is rewritten rather than left pointing at a fixed bug.

### Filed, not fixed here

- [[bug-a-a-variant-record-with-a-shortstring-branch-is-four-bytes-larger-than-fpc]]
  -- 16 before, 12 after, FPC says 8. The field half is fixed; the variant part's
  base is a different mechanism and may duplicate
  [[bug-p-a-tagged-variant-record-is-padded-to-eight]].
- [[bug-a-test-string-n-container-strides-is-compiled-and-never-asserted]] -- no
  expect_same line names it, and its `dyn2dvals` row is 0 at the pin and at HEAD.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
