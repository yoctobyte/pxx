---
track: A
tags: [C]
prio: 30
type: bug
blocked-by: []
summary: "`static void (*handlers[16][4])(void);` was registered as a 1-D array of 4 pointers: in the `(*name[..])` declarator each `[` overwrote the dimension, so the last one won. `handlers[11][0] = f` then wrote past the end (SIGSEGV), and `handlers[irq][i]()` was \"expected C expression\" (Gibux irq.c at c3576a5). The file-scope typedef spelling `fptr h[3][2]` read only its first `[N]`. Both now keep every dimension, size to the product and record the shape, like any multi-dimensional array; the local spelling too."
status: done
owner: unassigned
---

# A two-dimensional function-pointer array keeps only its last dimension

Gibux c3576a5 (shared PCI interrupt lines) added
`static void (*handlers[16][PER_IRQ])(void)` to arch/x86_64/irq.c, and pxx
stopped compiling the kernel.

## Cause

- ParseCDeclType's `(*name[N])` arm stored each dimension into the same
  `fpArrLen`, so `[16][4]` became `[4]`.
- The file-scope typedef arm (`fptr t[N]`) read one `[N]` and left the
  second for the parser to trip over.

## Fix

- CTypeFnPtrNDims / CTypeFnPtrDims carry every dimension.
- Both the global and the local fn-pointer paths size the array by the
  product and set SymArrNDims/SymArrDimSpan, so `h[i][j]` strides by the row
  and `h[i][j](args)` resolves through the existing SymElemProcSig channel.

## Test

test/c_two_dimensional_function_pointer_array.c covers the raw and typedef
spellings at file and block scope, with stores, calls in a loop condition and
body, and sizeof. The output is gcc's. The 012ccaa92c compiler refuses it
("expected C expression").
