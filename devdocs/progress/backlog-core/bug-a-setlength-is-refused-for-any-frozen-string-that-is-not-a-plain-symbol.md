---
prio: 40
track: A
type: bug
status: backlog
summary: "SetLength on a frozen string compiles only for a plain symbol. `SetLength(p^, n)`, `SetLength(r.f, n)` and `SetLength(arr[0], n)` are refused with `error: SetLength expects a string variable in IR codegen` on EVERY target including x86-64, in both modes, and reproduce on the pinned compiler -- every backend's builtin -101 arm requires the argument to lower to an IR_LEA of a symbol. Pre-existing and unrelated to the byte prefix; it is why the reader matrix carries only the direct SetLength spelling."
---

# SetLength is refused for any frozen string that is not a plain symbol

```pascal
type TS10 = string[10]; TRec = record f: TS10; end;
var s: TS10; r: TRec; a: array[0..1] of TS10; p: ^TS10;
begin
  p := @s;
  SetLength(s, 3);       { ok, every target }
  SetLength(p^, 3);      { error: SetLength expects a string variable in IR codegen }
  SetLength(r.f, 3);     { same }
  SetLength(a[0], 3);    { same }
end.
```

Measured 2026-09-03 on x86-64 native, both modes, and **reproduced on the
pinned compiler with no flag**, so it predates the byte-prefix work entirely.
Not a width bug and not target-specific: it is the same shape in all seven
backends, because each `procIdx = -101` arm does

```pascal
left := IRA[argNode];
if IRKind[left] <> IR_LEA then Error('... SetLength expects a string variable');
si := IRA[left];                    { and then reads Syms[si].TypeKind }
```

so the arm needs both an address AND a symbol index, and takes the symbol index
from the LEA. A field, an element and a deref all produce a perfectly good
address that is not an `IR_LEA` of a symbol, and the kind the arm wants is
recoverable from the node without the symbol: `IRStrTkOf` / `IRFrozenKindOfAddr`
answer it for exactly these shapes, which is how the readers (`Length`, `Pos`,
`Copy`, comparison) were converted. The fix is the same move, applied to the
writer.

## Why it is worth doing

`SetLength` is the only builtin in the family that is on BOTH sides of the
layout -- it reads the prefix to find the buffer and writes one back. The reader
matrix in `test/test_shortstring_through_a_pointer.pas` is built around the
direct/deref/field triple precisely because that is where the byte-prefix
defects have lived, and this refusal is why only the DIRECT SetLength row is in
it. Closing this adds the deref, field and element rows to a file whose rows are
all relations and whose expected output is byte-identical to FPC 3.2.2.

FPC accepts all four spellings.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]
[[bug-a-setlength-on-a-frozen-string-is-unsupported-on-riscv32]]
