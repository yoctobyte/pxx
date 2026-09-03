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

## It is TWO causes, not one arm — measured 2026-09-03 (frankA), HEAD `f8797c139`

The body above says all three shapes die in the `-101` arm. They do not. The
element shape never reaches it: it is misrouted by the CLASSIFIER and reports a
different error, about a different concept.

| target | frozen `string[10]` | managed `AnsiString` |
| --- | --- | --- |
| plain symbol | ok | ok |
| `p^` (deref) | `SetLength expects a string variable in IR codegen` | ok |
| `r.f` (field) | `SetLength expects a string variable in IR codegen` | ok |
| `sa[0]` (static array element) | **`SetLength expects an ARRAY variable`** | ok |
| `da[0]` (dyn array element) | **`SetLength expects an ARRAY variable`** | ok |

**THE MANAGED COLUMN IS THE ORACLE AND IT IS ALL GREEN.** That is the most
useful thing in this table: the address-based path already exists, is already
proven through a field, an element and a deref, and this ticket is the frozen
ANALOGUE of a working mechanism rather than new machinery. `IR_SETLEN_STR` is
that path (`defs.inc:1137`: "reached through ANY lvalue (symbol, record/class
field, var-param field, index, deref); IRA = target slot-ADDRESS node") — but
it calls `PXXStrSetLen(addr, n)`, which reallocates a heap block, so a frozen
inline string cannot ride it. The same line says so: "Frozen inline strings
keep the `-101` store-length path." The frozen analogue is a store, not a
realloc.

**CAUSE 1 — the classifier, `pasparser_stmt.inc` (the `slIsArrTarget` block).**
The `AN_INDEX` arm is `slIsArrTarget := True` unconditionally, commented
"nested dynamic sub-array". `x[0]` is genuinely ambiguous — for `array of array
of Integer` it IS the sub-array — so the arm has to ask what the ELEMENT is,
and it never asks. A frozen element therefore goes to the dyn-array `-102` arm
and is refused as not-an-array. The managed element survives only because
`-102` also handles `tyAnsiString`. The neighbouring `AN_FIELD` and `AN_DEREF`
arms already interrogate the target (`RecFieldType`, `SymPtrElemStrTk`); the
index arm is the one that assumes.

**CAUSE 2 — the writer, six backends.** `EmitStoreStrLen(idx)` in `symtab.inc`
is symbol-based and x86-64 alone calls it that way; the five cross backends
already have address-based helpers (`EmitStoreStrLen386(lenReg, bufReg, dstTk)`
and siblings, all taking a buffer REGISTER and a kind, not a symbol). So the
writer half is smaller than "six backends" suggests — x86-64 needs an
address-based variant, and the six `-101` arms need to accept an address node
instead of requiring `IRKind = IR_LEA` and reading the symbol out of it. The
model is two arms up in the same file: `specialId = 100` already reaches
through an `IR_LOAD_MEM` to the `IR_INDEX`/`IR_FIELD` underneath and publishes
to that address.

**FIXING ONLY CAUSE 1 IS NOT LANDABLE.** It moves the element shape off the
wrong error and onto the right broken arm — no program compiles that did not
compile before. The two halves land together or not at all, which is why this
was banked rather than half-done.

**NOT STARTED, DELIBERATELY, AND THIS IS THE COORDINATION THE TICKET NEEDS.**
`SetLength` is the only builtin on BOTH sides of the layout — it reads the
prefix to find the buffer and writes one back — so its `-101` arms are the ones
most exposed to the phase-4 flip, which is unreleased, the owner's alone, and
sequenced to go last with nothing else in flight. Six backend arms rewritten
underneath it is the collision that sequencing exists to prevent. Start this
the moment the flip lands; frankb-78 was told before the diagnosis began.
