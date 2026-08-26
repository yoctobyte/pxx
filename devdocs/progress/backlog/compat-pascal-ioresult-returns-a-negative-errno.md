---
track: B
prio: 55
type: bug
blocked-by: []
summary: "IOResult returns the raw negative errno (-2 for a missing file, -13 for permission denied) where FPC returns the positive DOS-style code (2, 5). Code written as `if IOResult = 2` silently takes the wrong branch."
status: backlog
---

# `IOResult` returns a negative errno instead of an FPC code

Found 2026-08-20 by an FPC differential probe over file I/O, alongside
`bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line`.

```pascal
AssignFile(t, 'definitely_missing_file_xyz');
{$I-} Reset(t); {$I+}
writeln(IOResult);
```

| case | FPC | pxx |
| --- | --- | --- |
| missing file | 2 | **-2** |
| permission denied | 5 | **-13** |
| success | 0 | 0 |

pxx passes the negative errno straight through (`SetIO(Integer(n))` in
`lib/rtl/textfile.pas`). FPC reports the DOS-heritage code: 2 = file not
found, 3 = path not found, 5 = access denied, 6 = invalid handle, 100 = disk
read past EOF, 101 = disk full, 103 = file not open, 106 = invalid numeric
input.

It is **compat**, not a crash: the value is nonzero either way, so `if
IOResult <> 0` — how most code spells it — behaves the same. Code that tests
for a specific cause (`if IOResult = 2 then ...`, an entirely normal thing to
write) silently takes the wrong branch, which is why it is a bug ticket and
not a note.

The map belongs next to `SetIO` in `lib/rtl/textfile.pas`: translate the errno
at the point it is recorded, so every caller sees FPC's numbering. Keep the raw
errno out of the public value entirely rather than translating at each call
site — one concept, one place.

Track B (`lib/rtl`).
