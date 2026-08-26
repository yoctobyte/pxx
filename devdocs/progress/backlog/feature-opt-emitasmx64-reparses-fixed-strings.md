---
prio: 60
track: A+O
---

# `EmitAsmX64` re-parses the same hardcoded assembly strings on every compile — ~12% of a NilPy compile

- **Type:** feature (codegen — compile-time cost) — **Track O** (file-ownership
  **Track A**: `compiler/ir_codegen.inc`, `compiler/asmtext*.inc`).
- **Opened:** 2026-08-26, by the Track O worker on
  [[feature-opt-o3-register-pressure]]. Filed rather than fixed: it is not a
  codegen-quality problem, it is an algorithmic one in a different file set,
  and the register-pressure ticket is about the emitted code.

## The measurement

Sampling profile (`bench-o/pxxprof`, see the parent ticket for why `perf` is
unusable on this box) of the compiler compiling a **one-line** NilPy file,
compiler built at `-O3`, sha `e7c0d1d2a`:

| symbol | share |
| --- | --- |
| `AsmTextLine` | 3.93% |
| `AsmTextSlice` | 1.75% |
| `AsmTextCharAt` | 1.56% |
| `AsmTextTrim` | 1.23% |
| `AsmTextIsSpace` | 1.08% |
| `AsmTextOperand` | 0.98% |
| `AsmTextCStr` | 0.69% |
| `EmitAsmX64` | 1.13% |
| **total** | **~12.4%** |

That is the *text* assembler — `AsmTextLine` tokenising strings like
`'mov rax, [@glob]'` character by character — running while compiling a file
that contains no inline assembly at all.

## Why it fires

The runtime blob emitters (`EmitAcquireHeapLock`, `EmitHeapFreeLocked`,
`EmitAnsiStrRetainLocked`, `EmitReadLine`, the object blobs, ...) are written as
`EmitAsmX64(['mov rdi, rax', 'push rcx', ...])`. That is genuinely nicer to read
than a wall of `EmitB($48); EmitB($89); EmitB($C7);` — the file says so
explicitly, and standing policy forbids the EmitB-rewrite campaign that would
remove it. So the readability is not the thing to attack.

What is attackable is that the **strings are compile-time constants and the
parse result never varies**. The same ~thousand fixed lines are re-lexed on
every single compile, of every program, on every target.

## Options (unranked — this needs a design call, not a patch)

1. **Memoise per string.** A hash map from the literal line to its encoded
   bytes, filled on first use. Smallest change; keeps every call site as-is.
   Care needed: a line with a `%`/`@glob` placeholder encodes differently per
   argument, so the key must include the substituted values (or such lines opt
   out).
2. **Hoist the blob emission.** Most of these blobs are emitted once per
   program into a fixed prelude. Encode them once into a byte array at
   compiler startup rather than at each emission site.
3. **Precompute at build time.** A generator turns the fixed `EmitAsmX64`
   lists into `EmitBytes([...])` arrays as part of the build, keeping the
   assembly text as the source of truth and never parsing it at runtime. Most
   invasive, largest win, and it does not touch the readability the policy
   protects.

## Acceptance
The `AsmText*` share of a one-line NilPy compile drops to noise, with the
compiler's emitted output byte-identical before and after (this changes *when*
bytes are computed, never *which* bytes).

## Links
Parent [[feature-opt-o3-register-pressure]] ·
[[bug-a-fpc-seed-drift-emitasmx64-forward]] ·
[[bug-emitasmx64-heap-helpers-oom-selfhost]]
