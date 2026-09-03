---
prio: 60
track: A
type: bug
status: backlog
summary: "`arr[1] := 'hello'` for `array[0..2] of string[10]` bus-errors on xtensa in the DEFAULT (8-byte prefix) mode -- both ABIs, at the pin, and only on the elements whose offset is not 4-aligned. SizeOf is 18, so element 1 starts at offset 18 and the 8-byte length-prefix store is unaligned; xtensa traps it. arr[0] and arr[2] are fine. Correct under -dPXX_SHORTSTRING (1-byte prefix) and on every other target."
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
