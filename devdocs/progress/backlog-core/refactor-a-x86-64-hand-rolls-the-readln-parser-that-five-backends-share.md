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

**THAT CENSUS HAS NOW BEEN RUN — 2026-09-18, and it paid for itself.** Eight
fixtures x five targets (x86-64, i386, riscv32, arm32, aarch64), fifteen input
shapes: blanks before a sign, a tab before a sign, leading zeros, an in-range
value into a `Byte`, two `Char`s from one line, two integers on one line, a
second integer past end of line, a string taking the rest of a line with its
blanks, a `string[N]` clamp, a `-` with no digits, `300` into a `Byte`, `40000`
into a `SmallInt`, `x9` into an `Integer`, the read/readln/Eof interleave, and
the character scan loop. **All five targets are byte-identical on every one.**
So the parsers DO agree, empirically, and the deletion is that much safer.

**It also found a real bug that no fixture covered, in BOTH spellings**:
`read(c: Char)` never handed over the `#10` that ends a line, so the canonical
`while not Eof do read(c)` scanner stepped silently from the last character of
one line to the first of the next. Fixed the same day in both readers
(`test_read_char_preserves_the_line_terminator.pas`). That is the argument for
this ticket restated as evidence rather than as a worry: two spellings of one
parser were wrong in the SAME way and nothing compared them to an oracle.

Two divergences from FPC survive and are filed separately —
[[bug-a-readln-diverges-from-fpc-on-a-malformed-number-and-on-a-char-read-from-an-empty-line]].
Neither is a disagreement between our own backends.
