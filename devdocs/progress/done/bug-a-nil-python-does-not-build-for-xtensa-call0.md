---
track: A
prio: 40
type: bug
blocked-by: []
status: done
found-by: frankd-90 (2026-09-28, a two-line Nil Python program built for --xtensa-abi=call0 on v447 and v448)
summary: "Nil Python did not build for xtensa Call0 at all: `x = 1; print(x)` failed with `addi immediate displacement 128 is outside the encodable range` in the appended pyeval.pas. The Call0 backend popped a call's argument block with ONE `addi sp, sp, nArgs*4`, and pyeval's 32-argument closure bridge is 128 bytes, one past addi's range. XtensaAddSp now splits the pop into in-range steps at all 13 variable-sized sites. Hosted xtensa also refused every Nil Python program ('a heap arena needs mmap'), but nothing on xtensa reads that arena, so the refusal is gone. Hosted Nil Python now RUNS on xtensa, on both ABIs."
owner: ""
---

# Nil Python does not build for xtensa Call0

```
$ printf 'x = 1\nprint(x)\n' > one.py
$ pascal26 --target=xtensa --xtensa-abi=call0 --platform=posix --xtensa-soft-mulhigh one.py one
pascal26:3407: error: target xtensa: addi immediate displacement 128 is outside
the encodable range -128..127; the code is too large for this branch form
  in: ./compiler/builtin/pyeval.pas
```

It failed on v447 and v448. The windowed ABI was not affected.

## Two walls, one behind the other

**1. The argument-block pop.** On Call0 the caller pushes the arguments and
pops them after the call with `addi sp, sp, nArgs*4`. addi encodes
-128..127, and nothing checked that before emitting. pyeval's closure bridge
makes a 32-argument indirect call, which is 128 bytes. It is appended to
every Nil Python program, so no Nil Python program could build.

The fix is `XtensaAddSp` in `ir_codegen_xtensa.inc`, which splits the
adjustment into in-range steps of 112, so sp stays 16-aligned between steps.
It does not use a scratch register: every site runs right after a call,
where a2/a3 hold the result. All 13 sites with a computed immediate (argument
blocks, spill counts, argFree) go through it. The sites with literal
immediates (-16, 16, EXC_FRAME_SIZE_XT) are in range and stay as they are.

**2. Hosted xtensa refused Nil Python.** Behind the first wall, a hosted
build stopped with "a heap arena needs mmap and EmitMmapArena has no xtensa
arm". The first cut added that arm. `qemu-xtensa -strace` then showed that it
called syscall 90, which is **mincore** on xtensa
(`mincore(0,268435456,...) = -1 ENOMEM`), and the programs passed anyway. That
could only happen if nothing reads the arena. Nothing does: the only reader
of BSS_HEAP_PTR/BSS_HEAP_END is the x86-64 inline allocator (symtab.inc).
Xtensa allocates through builtinheap's HeapMmap, whose xtensa arm (mmap2 =
80, flags $802) was already measured. So the refusal is lifted, and no
mapping is added. With the fix, `-strace` shows exactly one
`mmap2(NULL,268435456,...,MAP_PRIVATE|MAP_ANONYMOUS,-1,0)`, the heap's own.

A large Nil Python program on Call0 then needs `--xtensa-long-calls`, as it
already did on the windowed ABI. The compiler names that flag itself.

## Measured (2026-09-28)

- `test/test_xtensa_call0_wide_argument_block.pas`: 32 Integers (128 bytes),
  20 Int64s (160 bytes) and a virtual method with 31 Integers plus Self,
  direct and through a procvar, 200 times in a loop, then guards read.
  - On Call0 the output equals FPC 3.2.2's and pxx x86-64's.
  - Control: the pinned v448 binary refuses it with the same "addi immediate
    displacement 128".
  - The windowed ABI refuses the 20-Int64 callee by name ("parameter frame
    offset out of range"). That is a separate, honest limit, so the row is
    Call0 only.
- `test/test_nilpy_cross32_values.py` on hosted xtensa matches its .expected,
  on Call0 and on the windowed ABI.

Rows are in `test-xtensa`, after the windowed aggregate and regex rows.

## Found on the way, not fixed here

A routine with 33 parameters crashes the compiler (SIGSEGV, no diagnostic),
at the SHIPPED cap of 32. The test was first written with 40 parameters and
hit this. It is recorded, with the unguarded staging arrays, in
bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment.
