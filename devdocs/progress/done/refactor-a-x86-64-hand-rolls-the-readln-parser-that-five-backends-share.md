---
slug: refactor-a-x86-64-hand-rolls-the-readln-parser-that-five-backends-share
title: "x86-64 hand-rolls the readln PARSER that five backends get from the builtin — the storage is shared now, the parsing is not"
type: refactor
track: A
prio: 40
status: done
created: 2026-09-18
owner: ""
summary: "IR_READLINE / IR_READ_VAR / IR_READ_DISCARD have two implementations: EmitReadLine + EmitEof + EmitReadVarParse in `ir_codegen.inc` (x86-64 only, ~250 lines of hand-emitted asm) and PXXReadLine / PXXStdinEof / PXXReadVar* in `builtinheap.pas` (i386, arm32, aarch64, riscv32, xtensa). They already disagreed in a way a user could see: on a 5000-byte stdin line the asm answered `Length=4095` and the builtin `4096`, same program, same input. THAT divergence is gone — both now take their STORAGE from PXXLineEnsure, so capacity cannot differ — but the parsing is still two independent bodies of code with nothing pinning them together. NO BLOCKER IS KNOWN: the frozen-string (`string[N]`) case looked like one and is not — measured 2026-09-18, `test_read_into_a_frozen_string_from_stdin_and_a_file` passes unchanged under `--target=riscv32` and `--target=i386`, and `ir_codegen_riscv32.inc:4225`'s `read/readln target type not supported` does not fire for it. So this is a straight deletion of the asm in favour of `FindProc`, the way `ir_codegen386.inc:2356` already does it."
---

# The family this closes

Three defects in one day, one shape, and naming the shape is worth more than
the three fixes: **a stdin bug surfaces at an innocent statement DOWNSTREAM of
the guilty one, so the wrong line of source gets read as the suspect.**

- the over-long line was truncated with its tail left in the fd, so one long
  line became two and **the NEXT readln** returned the remainder — every later
  read in the program shifted by one, and none of them looked wrong;
- `read(c: Char)` swallowed the `#10`, so `while not Eof do read(c)` stepped
  from the last character of one line to the first of the next — the *readln*
  after it answered `[2]` instead of `[42]`, and the READLN looked like the bug;
- a frozen build failed with `call to a runtime stub that was never emitted`,
  which names the ELF entry point and a missing driver call, and says nothing
  about `readln`.

In all three the instrument that would have caught it — the value you assert —
was correct at the guilty statement. That is why the remedy is structural
rather than three fixes: **one reader, one buffer, one place the terminator
policy is written down.** Two spellings of one behaviour do not drift because
someone is careless; they drift because nothing makes them meet, and each drift
lands on a different statement from the one that caused it.

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

## Log
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 295bcceb9.


# Resolution — 2026-09-18

Done. The asm is deleted and x86-64 takes the same four routes as everyone else.

**And the census that unblocked it was right about agreement and wrong about
completeness.** It compared the two readers on programs that BUILD, and there
was a whole build mode where one of them does not. Under
`-uPXX_MANAGED_STRING` — the frozen-string model `compiler.pas` itself is
compiled with — `readln` was broken on **all five targets**, three different
ways, one cause:

| | message | since |
| --- | --- | --- |
| i386 / arm32 / aarch64 / riscv32 / xtensa | `PXXReadLine not found` | predates the buffer work; reproduces on the pin |
| x86-64, any target type | `PXXLineEnsure not found in builtin unit` | `0ab100740`, this week — a regression I introduced |
| x86-64, frozen-string target | `call to a runtime stub that was never emitted` | reproduces on the pin |

All three are one thing: **nothing told the Pascal driver that a `read` token
implies builtinheap.** `DetectPascalRuntimeNeeds` already carries two
paragraphs saying, in those words, *the dependency was moved and this is where
it has to be paid* — once for floats, once for a frozen string written with a
field width. This is the third, and the asm reader is why nobody had paid it:
x86-64 was self-contained, so the pull looked cross-target-only, and the five
targets that needed it were failing quietly in a mode no row covers.

The third row is the one that argues for the deletion rather than against it:
the builtin reads a frozen string correctly on i386 and riscv32, and the asm
sent one through its managed arm, which calls an AnsiString stub a frozen build
never emits. **Deleting the asm FIXED a target.** A de-duplication that was
also a fix.

## What changed

- `ir_codegen.inc`: `EmitReadLine`, `EmitEof` and `EmitReadVarParse` deleted,
  **285 lines**. The three IR arms and the `Eof` special now `FindProc` +
  `EmitCallProc` exactly as `ir_codegen386.inc` does; only the argument
  registers differ. `movzx rax, al` after `PXXStdinEof`, because a Pascal
  Boolean result is one byte and the deleted asm zeroed the register by
  construction.
- `pasparser_prog.inc`: a `read`/`readln` token, and the `Eof` identifier, pull
  builtinheap. Costs nothing in the default profile — `PXX_MANAGED_STRING`
  already forces `needsHeap` — so the whole effect is on frozen builds.
- `defs.inc` + `pasparser_prog.inc`: the six driver-owned bss slots
  (`BSS_LINE_BUF`, `_LEN`, `_TEXTLEN`, `_POS`, `BSS_PEEK_VALID`, `_BYTE`) are
  gone. They were the asm reader's private state, reserved in every Pascal
  program on every target — including the five that never referenced them and
  ESP, whose PAL refuses fd 0.
- `test/test_readln_in_a_frozen_string_build.pas` + two Makefile rows
  (x86-64 and i386). **Positive control: the pinned compiler refuses this
  program on both.** Values are FPC 3.2.2's own.

## Measured

Same source, only the compiler differing — `e50170cc775a` (before) against
`68c4f338990e` (after):

| | code | bss |
| --- | --- | --- |
| `test_readln.pas`, x86-64 | 72,042 -> **68,596** (-3,446) | 38,480 -> 38,432 (-48) |
| `hello.pas`, x86-64 | 67,486 -> 67,486 (0) | 38,444 -> 38,396 (-48) |
| `test_readln.pas`, i386 | 109,365 -> 109,365 (0) | 34,188 -> 34,140 (-48) |

The 48 bytes are every Pascal program on every target; the size canary records
-40 on all four bare-ESP subjects, which is the half that had no reader at all.

Parity: five fixtures (`test_readln`, the over-long line, the Char terminator,
the frozen string from stdin and a file, `test_eof_stdin`) x five targets
(x86-64, i386, aarch64, arm32, riscv32) — **byte-identical output on all
twenty-five**, and the x86-64 column matches its `.expected` rows.
