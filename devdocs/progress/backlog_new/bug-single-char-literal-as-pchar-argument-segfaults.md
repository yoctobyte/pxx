---
track: P
prio: 65
type: bug
blocked-by: []
summary: "A ONE-character literal passed where a PChar parameter is expected segfaults: `StrCat(buf, '-')` faults, `StrCat(buf, '--')` works. The single-quoted literal types as Char rather than as a string, so its ORDINAL is passed as the pointer and the callee dereferences address 45. FPC converts it to a pointer to a NUL-terminated one-character string. Pre-existing — it hits StrCopy/StrCat/StrPos as much as anything new."
status: backlog
owner: unassigned
---

# `StrCat(buf, '-')` segfaults; `StrCat(buf, '--')` is fine

Found 2026-08-25 by Track B while testing the PChar family
(`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`). Not caused by that
work — the same fault is reachable through `StrCopy` and `StrCat`, which have
been in `lib/rtl/strings.pas` all along. Nothing had ever passed a
one-character literal to them.

## Repro (nar5.pas)

```pascal
program nar5;
uses sysutils;
var buf: array[0..63] of Char; i: Integer;
begin
  for i := 0 to 63 do buf[i] := '#';
  StrCopy(@buf[0], 'x');
  StrCat(@buf[0], '-');        { <-- faults here }
  Writeln(StrPas(@buf[0]));
end.
```

| compiler | result |
| --- | --- |
| `fpc -O- -Mobjfpc -Sh` | prints `x-` |
| pxx (pinned stable) | **segfault**, exit 139 |

Note `StrCopy(@buf[0], 'x')` on the line above does NOT fault — it writes
through `Source[i]`, and reading address 120 happens to be mapped often enough
to get away with it. The fault surfaces at whichever call first touches an
unmapped low address. That is the worst shape: the same defect is a crash on one
line and silent garbage on another.

## Mechanism

A single-quoted one-character literal types as `Char`. In an argument position
whose parameter is `PChar`, pxx passes the character's ORDINAL where the
pointer goes, so the callee dereferences address 45 for `'-'`. Two characters
or more type as a string and convert correctly, which is why the boundary is
exactly at length 1.

FPC/Delphi: a character literal in a PChar context converts to a pointer to a
NUL-terminated one-character string. Same rule as the empty literal `''`, which
must become a pointer to a lone `#0` — worth checking in the same fix.

## Why it matters

Every classic PChar call site takes single characters: separators, path
delimiters, `'/'`, `'-'`, `','`. It is also invisible in review — the call reads
correctly and the type checker accepts it. And it degrades to a *wrong value*
rather than a crash whenever the ordinal happens to land on a mapped page,
which is the failure mode this repo treats as expensive
(`devdocs/dev/debugging-playbook.md`).

Sibling check while fixing: any other argument position that converts Char to a
pointer type, and the `''` case above.

## Track B workaround in place

`test/lib_strings_pchar.pas` builds the chained-append case with two-character
literals and notes this slug. No `lib/rtl` code was reshaped — the library never
passes a one-character literal to a PChar parameter.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the repro above
printing `x-` and exiting 0.
