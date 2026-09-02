---
prio: 55
track: A
type: bug
status: backlog
summary: "`p^[1]` for `p: ^string[10]` reads a BLANK on all four converted backends under -dPXX_SHORTSTRING at 764dc3a30, where `s[1]` and `r.f[1]` both read 'h' in the same run. So the index ORIGIN is right in general and wrong specifically through a deref -- the chars start at base+prefix and this path is still adding the wide offset. Survives the four-cause fix; caught by test_shortstring_through_a_pointer's `index deref` row."
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
