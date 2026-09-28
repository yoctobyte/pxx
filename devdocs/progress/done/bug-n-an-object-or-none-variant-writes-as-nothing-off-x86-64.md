---
track: N
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankB (C3 under QEMU, test_nilpy_keyword_call_tuple_on_a_skipped_default); narrowed by frankZ (a free procedure fails the same way, so it isn't keyword binding) and frankD (aarch64 fails too, so it isn't 32-bit)
tags: [nilpy, variant, write, cross-target, esp32, silently-wrong]
summary: "On every target except x86-64, writing an OBJECT-valued Variant (a tuple or list passed to a Pascal `const v: Variant` parameter) printed nothing where x86-64 prints `<object>`. Under a Nil Python main, an EMPTY one also printed nothing where x86-64 prints `None`. x86-64 writes a Variant inline, and every other backend calls the runtime PXXWriteVariant, which had deliberately left out both arms until bug-a-a-null-variant-renders-as-none-in-pascal was settled. It had been settled, but only for x86-64. PXXWriteVariant now prints `<object>`, and the new PXXWriteVariantPy prints `None` for an empty slot. The backends call it under a Nil Python main, through one shared WriteVariantHelperName."
owner: ""
---

# An object or None Variant writes as nothing off x86-64

```python
import 'kwpadprobe.pas' as kw        # procedure freegrid(...; const padx, pady: Variant = 0)
kw.freegrid(row=1, padx=(8, 6))
# x86-64: free  row=1 sticky=[] padx=<object> pady=None
# i386, arm32, aarch64, riscv32, xtensa, wasm32, and the C3:
#         free  row=1 sticky=[] padx= pady=
```

Scalar Variants in the same slot were right (`padx=8`), and so was keyword
binding. The object got there intact; only the write lost it.

## Cause

`writeln(v)` for a Variant is inline code on x86-64 (`EmitWriteVariant`,
ir_codegen.inc). It prints `<object>` for `VT_OBJECT`, and `None` for
`VT_EMPTY` when `PyProgramMode` is set, since a Pascal main prints nothing,
which is FPC's answer. The other six backends call the runtime
`PXXWriteVariant` (builtinheap.pas). Its header said it left out "two arms
x86-64 has, deliberately", until bug-a-a-null-variant-renders-as-none-in-pascal
settled the spelling. That ticket did settle it, but only in the inline
writer.

## The fix

- `PXXWriteVariant` prints `<object>` for tag 7, in either language.
- `PXXWriteVariantPy` prints `None` for tag 0, and otherwise defers to
  `PXXWriteVariant`. The runtime cannot see PyProgramMode, so the caller makes
  the split, as `PXXVarBinOpPas` already does.
- `WriteVariantHelperName` (symtab.inc) picks the name. i386, arm32, aarch64,
  riscv32, xtensa and wasm32 all call through it, so the six sites cannot
  drift apart.

## Measured (2026-09-29, fixedpoint 4e84558a4acd)

- test_nilpy_keyword_call_tuple_on_a_skipped_default equals its expectation
  (x86-64's) on x86-64, i386, arm32, aarch64, riscv32, xtensa windowed/call0
  and wasm32. It had only an x86-64 row, which is how this stayed unseen. It
  now has rows on the other seven.
- A Pascal main is unchanged: an empty Variant still writes as nothing, the
  same as FPC 3.2.2, on x86-64, i386, arm32, aarch64, riscv32 and wasm32.
- The 132 cross-target Makefile blocks that compile a Nil Python source were
  run with the previous compiler and with this one. Nothing went from pass to
  fail. (The two that went from fail to pass are the wasm32 initialization and
  finalization rows that ride on the same branch.)
