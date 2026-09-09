---
slug: bug-a-a-threadvar-read-in-a-child-thread-faults-once-the-programs-globals-cross-a-size-boundary
title: "A threadvar read in a CHILD thread segfaults once the program's globals cross a size boundary — one extra Integer is enough"
track: A
prio: 60
type: bug
status: open
owner: ""
found: 2026-09-09
found-by: frankS
blocked-by: []
tags: [threads, threadvar, codegen, x86-64]
summary: "MEASURED 2026-09-09 at compiler 470240dd0eb5. Add ONE unused Integer to the program var block of test/test_a_threadvar_is_per_thread.pas and it SEGFAULTS -- in the child thread, at the first read of the threadvar, before any output. The file is green at HEAD, so the shipped test sits one variable from a crash. The fault address is `0xffffffffe03fad30`: a 32-bit value SIGN-EXTENDED and used as a pointer, which is why the main thread never faults (its block is low) and a child does (its block is carved off a thread stack, which is mapped high with bit 31 set). The two builds do not differ by an offset -- they emit STRUCTURALLY DIFFERENT code for the same source: with the smaller var block the parameter read is `mov -0x8(%rbp),%rax`, with the larger one the same source position emits `mov %gs:0x0,%rax; mov (%rax),%rax`. NO PINNED CONTROL EXISTS: the pin refuses program-level `threadvar` outright (`expected 'begin' before 'threadvar'`), so this cannot be bisected against v407 and is young rather than long-standing. Found while repairing the flaky race control in that same file -- the repair needs one more loop variable, which is exactly what trips this, so [[regression-test-threads-test-a-threadvar-is-per-thread]] is blocked on this."
---

# One more variable and the child thread faults

## Repro, three commands

```
sed 's/^  i, kept, zeroed, clean, raced: Integer;$/  i, kept, zeroed, clean, raced, unused_: Integer;/' \
    test/test_a_threadvar_is_per_thread.pas > /tmp/tv1.pas
./compiler/pascal26 --threadsafe /tmp/tv1.pas /tmp/tv1
/tmp/tv1          # Segmentation fault, no output at all
```

The unmodified file at the same compiler prints `THREADVAR OK`, rc=0. The added
variable is never read or written.

## What was measured

- **Where.** gdb: `Thread 2 ... SIGSEGV ... in Body (arg=0x0) at
  test_a_threadvar_is_per_thread.pas:16`, which is
  `if mine = 0 then Zero[idx] := 1 else Zero[idx] := 0;` — the first read of the
  threadvar in the child. The main thread's own reads are fine.
- **What the address looks like.** `rax = 0xffffffffe03fad30` at the faulting
  instruction. The low 32 bits are `0xe03fad30`, bit 31 set. That is the shape
  of a 64-bit address truncated to 32 bits and sign-extended, not of a null or
  a small offset.
- **Why the size matters, and why "boundary" and not "amount".** A child's
  threadvar block is carved off its own stack (the file's own header says so),
  and thread stacks are mapped high; the main thread's block is not. So a
  truncating computation is harmless for main and fatal for a child, and it only
  becomes fatal once the block lands where bit 31 is set.
- **The cliff, isolated.** Reduced to a 40-line program: with three padding
  Integers it runs, with four it faults. Same source otherwise.
- **The two builds are not the same code.** Disassembling `Body` at the same
  source position: three pads emits `mov -0x8(%rbp),%rax` (read the parameter),
  four pads emits `mov %gs:0x0,%rax; mov (%rax),%rax` (a TLS block load). **A
  var-block size is selecting a different lowering**, which is the part to chase
  first — an offset bug would leave the instruction stream the same shape.

## What is NOT established

The sign-extension reading is the best fit for the address and the
main-versus-child asymmetry, and it is **inferred from one faulting register**,
not from the codegen. The structural difference in the disassembly is the harder
fact and it may be the whole cause, with the address being downstream of it. Do
not quote the truncation as the mechanism until someone has read the emitter.

## No pinned control

`stable_linux_amd64/default/pinned` refuses the file outright —
`pascal26:33: error: expected 'begin' before 'threadvar'`. Program-level
`threadvar` postdates the pin, so there is no earlier binary to compare against
and this is not a regression from anything shipped.

## How it was found

Not by looking for it. The auto-filed
[[regression-test-threads-test-a-threadvar-is-per-thread]] is a FLAKY RACE
CONTROL (see that ticket), and the obvious repair — retry the round until the
control races — needs one more loop variable in that var block. The repair
segfaulted, which read exactly like the repair being wrong. It was not.
**A latent codegen bug sitting one declaration away from a live test is
invisible until someone adds a declaration**, and what they will conclude is
that their own edit is broken.
