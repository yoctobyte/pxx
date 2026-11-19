---
slug: feature-a-a-typed-const-array-of-string-literals-is-baked-into-data
track: A
prio: 40
type: feature
status: done
created: 2026-11-19
owner: claude-dupwt
tags: [esp, flash, codesize, typed-const]
blocked-by: []
summary: "A typed const array of AnsiString whose elements are all literals is now initialised .data (one pointer fixup per slot to the interned static literal) instead of BSS plus a startup store per element. The startup path cost ~40 B of code per element: a 256-entry table went from 12,674 to 1,114 B of code on riscv32 ESP. The NilPy C3 demo's code drops 12,268 B (pylib's PyChar1Tab). SRAM is unchanged, because .data stays writable ({$J+}). '' bakes as nil, as an empty AnsiString must. Along the way, a latent bug was fixed: the numeric element path never sets PendingInitKind, so slots rewound by a bake must be cleared, or the next array inherits the kind."
---

# A typed const array of string literals is baked into .data

TryBakeConstArrayIntoData (symtab.inc) gained a tyAnsiString arm: all
elements must be PendingInitKind 1 (a literal). Each is interned (the static
[meta][rc][len] handle) and its slot gets AddDataPtrFix to Offset + 8, the
word the startup store would have written. ShortString/string[N] are
excluded (inline buffers). '' leaves a zero slot, since an empty AnsiString is
nil and `s = ''` is tested as nil.

## The bug the self-host found

The first version passed every hand test and then failed the self-host
("cannot assign ShortString to Byte" in main). Bisecting the bake count
pointed at asmdisasm_x64.inc's CcNames; the failing store was the NEXT
array's (`STUB`, Byte). The element-recording path for numeric arrays does
not write PendingInitKind and relies on 0. A bake rewinds PendingInitCount, so
the next declaration reuses those slots; string slots left Kind = 1, and STUB's
bytes were startup-stored as strings. The bake now clears Kind and ValAux on
the slots it rewinds.

## Measured (riscv32 --platform=esp)

- 256 x one-char AnsiString const: code 12,674 to 1,114 B, bss 1,284 to 260 B
- nilpy-c3 demo: code 729,772 to 717,504 B (-12,268); our SRAM 11,216 to
  11,248 B (PyChar1Tab moves from .bss to writable .data); qemu-assert OK
- hosted x86-64: a test of escapes, UTF-8, '', copy-on-write, {$J+}
  reassignment and concatenation gives output identical to the latest compiler
- gate quick (incl. the FPC seed canary) and test-emit-obj pass
