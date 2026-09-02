---
prio: 60
track: A
type: bug
status: backlog
summary: "`r.f = 'hello'` for a `string[10]` RECORD FIELD segfaults on x86-64 and riscv32 and returns FALSE on aarch64 and arm32, under -dPXX_SHORTSTRING at 764dc3a30 -- i.e. AFTER the four-cause frozen-prefix fix. The direct and deref spellings (`s = 'hello'`, `p^ = 'hello'`) are GREEN in the same run on all four, which is what makes this a fifth reader and not a leftover of the four. Caught by test_shortstring_through_a_pointer's `compare field to literal` row; it is also the row that now truncates that file on two backends."
---

# Comparing a frozen record FIELD to a literal crashes or answers FALSE

```pascal
type TS10 = string[10]; TRec = record f: TS10; end;
var r: TRec;
begin
  r.f := 'hello';
  if r.f = 'hello' then ...   { segfault on x86-64 and riscv32,
                                FALSE on aarch64 and arm32 }
end.
```

Measured 2026-09-02 at `764dc3a30`, compiler `e81a80c4621c`, under
`-dPXX_SHORTSTRING`. Default mode is correct on all four.

## Why this is a FIFTH cause, not a remnant

`764dc3a30` fixed four distinct readers and its own summary says so. In the
**same run** that produces the failures above, `s = 'hello'` and `p^ = 'hello'`
are both green on all four backends — so the comparison arm itself now resolves
the frozen kind for a variable and for a deref, and does not for a FIELD. The
field operand reaches it by a path none of the four fixes covers.

The two failure modes are the same defect at two word sizes: a field operand
whose length is read at the wrong width gives a count in the hundreds of
millions, which the comparison either walks off (segfault) or short-circuits on
a length mismatch (FALSE).

## Where it is asserted

`test/test_shortstring_through_a_pointer.pas`, row `compare field to literal`.
That file is wired DEFAULT-only; this bug is one of the two reasons its
`-dPXX_SHORTSTRING` rows are still not wired.

It is also the current truncation point on x86-64 and riscv32 — a crashing row
costs every row behind it, so this bug is currently hiding the verdict of the
eleven rows that follow it.

[[bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]
