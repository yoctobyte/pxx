---
slug: bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length
track: A
prio: 60
type: bug
status: open
blocked-by: []
found: 2026-09-02
found-by: frankC
owner:
summary: "On wasm32 ONLY, comparing two shortstrings is FALSE for every length 1..8, including a variable against itself-by-value. The STORE is correct -- identical bytes, Length and s[1] to native, and the value prints correctly -- so the defect is in a READER of the length prefix, not a writer. Correct on riscv32 and x86-64; reproduced under the PINNED compiler, so it predates the phase-2 shortstring work. Causes test_char_into_shortstring_via_pointer to fail its own assertions on wasm32 while printing the right values."
---

# wasm32 shortstring comparison is wrong at every length

## Repro

```pascal
type TS = string[8];
procedure T(const lit: TS);
var a: TS;
begin
  a := lit;
  if a = lit then WriteLn('OK') else WriteLn('WRONG');
end;
begin T('a'); T('ab'); ... T('abcdefgh'); end.
```

```
wasm32   len=1..8   ALL WRONG
riscv32  len=1..8   all OK
x86-64   len=1..8   all OK
```

## The isolating probe — why this is a READER bug, not a store bug

```pascal
s := 'abcde'; p := @s; p^ := c;   { c = 'X' }
```

|          | printed | Length | s[1] | `s = 'X'` | bytes 0..6 |
| ---      | ---     | ---    | ---  | ---       | ---        |
| x86-64   | `[X]`   | 1      | X    | OK        | 1 0 0 0 0 0 0 |
| wasm32   | `[X]`   | 1      | X    | **FAIL**  | 1 0 0 0 0 0 0 |

**Identical memory, identical length, identical indexing, identical output.**
Only the comparison differs. So the write path is right and some reader of the
length prefix is not.

This matters beyond the one row: the phase-2 shortstring census across all
backends counted `PXXWriteFrozenW` call sites, i.e. **writers**. Comparison is
a reader of the same layout and is in nobody's count. Anything that converts
writers to a 1-byte prefix without converting this reader changes which rows
pass rather than fixing them.

Note frankh-15 independently reports `s = 'hello'` FALSE on x86-64 and arm32
**under `-dPXX_SHORTSTRING`**, correct on aarch64 and riscv32. That is the same
reader class showing on different targets depending on flag state; this ticket
is the no-flag wasm32 instance. They may share a cause.

## Controls already run

- PINNED compiler reproduces both -> predates phase 2 and predates any local tree.
- `git diff HEAD -- lib/` clean when the pinned control ran, so the control is valid.
- riscv32 and x86-64 correct at every length -> wasm32-only.

## Do not

Do not make `test-wasm32` green by wiring these rows to a wasm32-specific
expectation. The five rows excluded from `test-wasm32` (a6d7bfc08) are excluded
because they are real.
