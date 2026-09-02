---
prio: 40
track: A
type: bug
status: backlog
summary: "SetLength(s, n) on a `string[N]` is a hard compile error on riscv32 -- `standard builtin calls not supported in bare-metal stage 1 (builtin id 101)`. Pre-existing, unrelated to the byte prefix, and it compiles on x86-64/aarch64/arm32. Pos and Copy on the same type DO compile on riscv32, so this is one missing builtin rather than a general gap. It cost the frozen-string reader matrix its two SetLength rows, which would otherwise cover a reader that appears in no census."
---

# SetLength on a frozen string is unsupported on riscv32

```pascal
type TS10 = string[10];
var s: TS10;
begin
  s := 'hello';
  SetLength(s, 3);   { pascal26: error: target riscv32: standard builtin calls
                       not supported in bare-metal stage 1 (builtin id 101) }
end.
```

Measured 2026-09-02, default mode, no `-dPXX_SHORTSTRING`. **`Pos` and `Copy` on
the same type both compile on riscv32**, checked one at a time, so this is a
single missing builtin and not a blanket bare-metal restriction.

## Why it is worth more than its size

`SetLength` **reads** the length prefix before it writes one, and every
call-site census phase 2 ran counted `PXXWriteFrozenW` — writers. Comparison,
`Copy`, `Pos` and `SetLength` appear in none of them, and the byte-prefix
defects have all been in readers. So `SetLength` belongs in
`test_shortstring_through_a_pointer.pas`'s reader matrix and had to be removed
from it, because a hard compile error on one target costs the whole file there.

Restore those two rows when this lands — the file says so at the point they
were removed.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]
