# Missing FPC surface found by the differential probe (Eoln, TSeekOrigin, Sorted, IncMonth)

- **Type:** feature gap — Track B (library), tag `compat`
- **Status:** backlog
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh` after widening it into file I/O,
  streams, containers and date arithmetic.
- **prio:** 35

Each is a hard "undefined"/"no such member" error, so none can miscompile —
they are missing surface, not wrong behaviour. Grouped because they were found
in one sweep and each is small.

## The items

1. **`Eoln(f)`** — `undefined variable (Eoln)`. `Eof` exists. Eoln is how
   character-at-a-time reading finds the end of a line, so its absence forces a
   readln-and-index workaround.

2. **`TSeekOrigin` constants** — `undefined variable (soFromBeginning)`.
   `TStream.Seek` itself exists; the origin constants
   (`soFromBeginning` / `soFromCurrent` / `soFromEnd`, and the modern
   `soBeginning` / `soCurrent` / `soEnd`) do not, so Seek cannot be called
   portably.

3. **`TStringList.Sorted`** — `no such member`. `Sort` (the one-shot method)
   exists; the `Sorted` *property*, which keeps the list ordered across
   subsequent `Add`s and switches `IndexOf` to a binary search, does not.
   Note the semantic difference from `Sort` when taking this on: setting
   `Sorted := True` changes where later `Add`s land, and FPC raises on `Insert`
   into a sorted list. Also missing alongside it: `Duplicates`
   (`dupIgnore`/`dupError`/`dupAccept`), which only has meaning when sorted.

4. **`IncMonth`** — `undefined variable`. The end-of-month clamp is the whole
   point and the part worth reading off FPC rather than deriving:
   `IncMonth(EncodeDate(2026,1,31), 1)` is **2026-02-28**, not an overflow into
   March.

`Append`, `FileExists`, `DeleteFile` and `IsLeapYear` were suspected in the same
sweep and all **exist and behave correctly** — the probe cases that seemed to
implicate them were actually failing on
`bug-p-writeln-text-rejects-char`. Checked individually before filing.

## Method note

Each has a probe case waiting in `tools/fpc_diff_probe.sh`, tagged `known`.
Whoever implements one should read the expectations off an FPC build rather
than from the documentation — `IncMonth`'s clamp and `Sorted`'s effect on `Add`
are both the kind of rule that is easy to state slightly wrong.
