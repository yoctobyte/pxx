---
track: A+S
type: bug
prio: 40
status: open
found: 2026-08-30
found-by: frankS
---

# The xtensa WINDOWED ABI bus-errors on frozen strings, Copy, and dynarray SetLength

Three constructs fault under `--xtensa-abi=windowed` and are correct under
Call0 (the default). All three predate the expression-stack fix in
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]] —
**verified against the pre-change compiler**, which bus-errors identically, so
this is not fallout from that work.

## Repro

`--target=xtensa --platform=posix --xtensa-abi=windowed --xtensa-soft-mulhigh`,
under `qemu-xtensa` 10.2.1. Each is correct on Call0 and on x86-64.

```pascal
program t; var a: string[8]; begin a := 'zz'; WriteLn(Length(a)); end.
{ Call0: 2    windowed: SIGBUS  -- no comparison, no concat: a frozen string alone }

program t; var s: AnsiString; begin s := 'abcdef'; WriteLn(Copy(s, 2, 3)); end.
{ Call0: bcd  windowed: SIGBUS }

program t; var i: Integer; a: array of Integer;
begin SetLength(a, 50); for i := 0 to 49 do a[i] := i * 3; WriteLn(a[49]); end.
{ Call0: 147  windowed: SIGBUS }
```

The frozen-string case is the one to start from: it is the smallest, it
involves no helper call that the other two share, and it says the fault is in
how a *frozen buffer's address* is formed under windowed rather than in `Copy`
or `SetLength` themselves.

## Why this is only visible now

Windowed is the ESP-IDF ABI, and nothing could run a hosted xtensa binary until
`feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle` landed the syscall,
exit and heap arms. On real IDF hardware these would have been three unexplained
crashes with no oracle to compare against.

**A caution for whoever takes it:** do not assume the windowed frame is the
suspect just because windowed is the failing arm. Call0 and windowed differ in
*two* independent ways — the register window, and the expression-stack direction
(`XtensaSlotOff`) — and the second was wrong on Call0 for months while windowed
was right. The arms are not "one correct, one broken"; they are two disciplines
that have each been wrong somewhere.

## Bound

Object-level plus observable output under qemu-xtensa 10.2.1, hosted profile,
both ABIs compared directly, at `e866cc16d4fe`. Not checked on real IDF
hardware.
