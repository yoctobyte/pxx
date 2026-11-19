---
track: P
prio: 30
type: bug
status: done
found: 2026-11-14
found-by: the kernels session (while testing --os=windows subprocess pipes)
blocked-by: []
summary: "`while not Eof(Input) do ReadLn(s)` on a pipe loses the first line, reads the rest, then loops for ever on empty lines: Eof(Input) never turns true. `Eof` with no argument, on the same input, is correct. Linux x86-64, also in stable_linux_amd64/default/pinned, so it is old. A parent reading such a child's stdout grows without bound (960 MB in a minute)."
---

# Eof(Input) on a pipe loses the first line and never ends

## Repro (Linux x86-64, current master and the pinned stable compiler)

```pascal
program eof2;
var s: string;
begin
  WriteLn('start');
  while not Eof(Input) do begin ReadLn(s); WriteLn('got: ', s); end;
end.
```

```
$ printf 'a\nb\n' | ./eof2 | head -4
start
got:
got: b
got:
```

Expected (and what `while not Eof do` gives on the same input):

```
start
got: a
got: b
```

## Notes

- Only the explicit `Eof(Input)` form is wrong; `Eof` (no argument) works.
  So the two are probably two code paths, and the explicit-file one does
  not share Input's buffer with ReadLn: its look-ahead read seems to consume
  the first line into a buffer ReadLn never sees, and after that the
  look-ahead keeps reporting "not at end".
- Not tested: `Eof(F)` on a text file assigned to a pipe, or `SeekEof(Input)`.
- Found while writing a child program for the --os=windows subprocess test;
  the same program misbehaves identically on Linux, so it is not a
  translator issue.


# Fixed 2026-11-19 (claude-dupwt)

**Cause: two stdin readers over one fd.** Bare `read`/`readln`/`Eof` go
through the console reader in builtinheap (PXXReadLine, PXXStdinEof: a line
buffer plus one peeked byte). `Eof(Input)`, `Eoln(Input)` and `Read(Input, ..)`
go through textfile's unbuffered `Input`. Each read fd 0 without knowing what
the other held. `Eof(Input)` peeked 'a' into Input, `ReadLn(s)` then read fd 0
from the '\n' (the lost first line), and the peeked 'a' stayed in Input for
ever, so `Eof(Input)` never turned true. Not pipe-specific: a redirected
regular file did the same. Mixing in the other direction failed too:
`Eof` with `ReadLn(Input, s)` lost the first byte.

**Fix: the two readers hand each other their pending byte.**
- builtinheap: `PXXStdinTakeHook` (nil without textfile, the
  `PXXDivZeroHook` pattern). The console takes textfile's held byte back
  (PXXStdinReclaim, at the top of PXXReadLine, PXXStdinEof and
  PXXReadDiscard) and puts it in front of its own pending bytes: into the slot
  it came from, else the peek slot. That byte is always the oldest one unread.
  `PXXStdinTakeConsole` gives textfile the console's next pending byte.
- textfile: an unbuffered fd-0 fill takes the console's byte before reading fd
  0. The initialization installs `TFStdinTake` as the hook.

Measured against fpc 3.2.2 on a pipe and a regular file: all four
`{Eof, Eof(Input)} x {ReadLn(s), ReadLn(Input, s)}` loops, plus a program
alternating `Read(Input, c)`, `ReadLn(s)`, `Read(i)`, `Read(Input, j)`,
`Eoln(Input)`, `ReadLn` and `Read(c)`. All agree byte for byte. Before the
fix, the same program read 3 for 3+4 and ran away.

257 Makefile rows whose tests read stdin, A/B with the change stashed and
applied: identical. The test also passes on riscv32, i386 and aarch64 under qemu.

Test: test_p_eof_of_input_shares_stdin_with_the_console_reader (row
test_eofinput26, fed on a pipe, under `timeout 10` so a regression fails instead
of hanging).

**Pin hazard, handled.** The first gate run went RED on "pinned builds live
lib/rtl": the pinned compiler (v455) builds live textfile against its own
builtin, which has neither new symbol. textfile's two references are now under
`{$ifdef PXX_BUILTIN_STDIN_HOOK}`, a define the live compiler predefines
(paslexer.inc PasInitDefines). The pin builds the old behaviour (checked: it
compiles the test and prints RUNAWAY), and the live compiler builds the fix.
Retire the define and both guards once a pin carries the handshake.
