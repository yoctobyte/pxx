---
track: P
prio: 25
type: compat
blocked-by: []
summary: "`string[20]` is a managed string with a length CAP, not a Turbo/FPC shortstring: SizeOf is 8 (a handle) where FPC says 21, and `ss[0]` — the length byte — reads #0 instead of Chr(Length(ss)). Truncation to the declared length does work, and every character operation agrees."
status: backlog
---

# `string[N]` caps the length but is not a shortstring

- **Track P** (Pascal frontend: the `string[N]` type), tag **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over strings.

## What differs

```pascal
type TS20 = string[20];
var ss: TS20;
begin
  ss := 'hello';
  Writeln(Length(ss), ' ', SizeOf(ss), ' ', Ord(ss[0]));
end.
```

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `Length(ss)` | 5 | 5 |
| assignment past the cap truncates | yes | yes |
| `SizeOf(ss)` | 21 | **8** |
| `Ord(ss[0])` (the length byte) | 5 | **0** |

Everything about the CHARACTERS agrees — assignment, truncation at 20,
indexing from 1, mutation through `ss[1]`, passing by value. What does not is
the storage: FPC lays a shortstring out as one length byte followed by N
characters, in place; pxx uses its managed string with a declared cap, so
`SizeOf` reports a handle and the `s[0]` length-byte idiom reads nothing.

## Why it is a compat item

`s[0]` is a Turbo Pascal idiom that FPC still honours and that real code does
use, but reading it here answers #0 rather than a wrong length, so a program
that uses it gets an obviously-empty answer rather than a plausible one. The
layout difference matters for the same reasons as
[[compat-pascal-subrange-storage-size]]: a record with a `string[N]` field, a
`file of TRec`, and anything handed to C see a pointer where FPC puts N+1
bytes in place.

Recorded rather than scheduled: making `string[N]` a real in-place shortstring
is a storage-model change, and the dialect deliberately has ONE string model.
The decision of whether to grow a second one belongs to Track U if it is ever
worth it.
