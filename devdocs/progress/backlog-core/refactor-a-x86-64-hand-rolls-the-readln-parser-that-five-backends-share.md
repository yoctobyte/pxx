---
slug: refactor-a-x86-64-hand-rolls-the-readln-parser-that-five-backends-share
title: "x86-64 hand-rolls the readln PARSER that five backends get from the builtin — the storage is shared now, the parsing is not"
type: refactor
track: A
prio: 40
status: new
created: 2026-09-18
owner: ""
summary: "IR_READLINE / IR_READ_VAR / IR_READ_DISCARD have two implementations: EmitReadLine + EmitEof + EmitReadVarParse in `ir_codegen.inc` (x86-64 only, ~250 lines of hand-emitted asm) and PXXReadLine / PXXStdinEof / PXXReadVar* in `builtinheap.pas` (i386, arm32, aarch64, riscv32, xtensa). They already disagreed in a way a user could see: on a 5000-byte stdin line the asm answered `Length=4095` and the builtin `4096`, same program, same input. THAT divergence is gone — both now take their STORAGE from PXXLineEnsure, so capacity cannot differ — but the parsing is still two independent bodies of code with nothing pinning them together. NO BLOCKER IS KNOWN: the frozen-string (`string[N]`) case looked like one and is not — measured 2026-09-18, `test_read_into_a_frozen_string_from_stdin_and_a_file` passes unchanged under `--target=riscv32` and `--target=i386`, and `ir_codegen_riscv32.inc:4225`'s `read/readln target type not supported` does not fire for it. So this is a straight deletion of the asm in favour of `FindProc`, the way `ir_codegen386.inc:2356` already does it."
---

# What is shared and what is not

| | x86-64 | i386 / arm32 / aarch64 / riscv32 / xtensa |
| --- | --- | --- |
| line storage | `PXXLineEnsure` | `PXXLineEnsure` |
| fill loop | `EmitReadLine` (asm) | `PXXReadLine` |
| `Eof` | `EmitEof` (asm) | `PXXStdinEof` |
| AnsiString target | `EmitReadVarParse` (asm) | `PXXReadVarStrM` |
| `string[N]` target | `EmitReadVarParse` (asm) | reaches `PXXReadVarStrM` and is correct |
| Char target | `EmitReadVarParse` (asm) | `PXXReadVarChar` |
| integer family | `EmitReadVarParse` (asm) | `PXXReadVarInt` |

# The work

Point x86-64's three arms at `FindProc('PXXReadLine' / 'PXXReadVar*' /
'PXXReadDiscard' / 'PXXStdinEof')` and delete `EmitReadLine`, `EmitEof` and
`EmitReadVarParse`. i386 is the worked example and it is the same ISA family.

Cost is a call per byte on a path that already does a `read(2)` syscall per
byte, so the performance argument for the asm does not survive contact with the
syscall it wraps.

# Do not sell this as "no observable difference"

It is not a tidy-up. The two spellings produced different values for one real
program until this morning, and no test would have caught it: `test_readln.pas`
IS cross-checked between i386 and x86-64 (`Makefile:26282`) — on input where
the two agree. `test_readln_line_longer_than_the_buffer.pas` is now
cross-checked the same way on input where they did not.

**The honest statement is that the parsers are not known to agree, not that
they do.** What has actually been run across backends, 2026-09-18, all green:
`test_readln`, `test_eof_stdin`, `test_read_into_a_frozen_string_from_stdin_and_a_file`
and the new long-line row, on x86-64, i386 and riscv32. What has NOT been
compared on any target but x86-64: whitespace before a sign, a `-` with no
digits after it, a value wider than its target, a `Char` read at end of line.
Running the existing fixtures under two more `--target=` flags is most of the
value in this ticket and costs minutes — do that first, whether or not the
deletion follows.
