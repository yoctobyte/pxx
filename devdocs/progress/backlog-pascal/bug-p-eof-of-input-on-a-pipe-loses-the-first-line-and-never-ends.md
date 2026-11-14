---
track: P
prio: 30
type: bug
status: open
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
