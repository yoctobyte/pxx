---
owner: claude-B
---

# Missing FPC surface found by the differential probe (Eoln, TSeekOrigin, Sorted, IncMonth)

- **Type:** feature gap — Track B (library), tag `compat`
- **Status:** done
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

## Resolution 2026-08-09 (Track B) — measured first; half of it was already done

The ticket's own method note says to read expectations off an FPC build rather
than the documentation. Applying that to the LIST as well as the values changed
what the work was: compiling each of the four items showed **two of them already
implemented** since this was filed on 2026-08-04.

| item | measured state | done |
| --- | --- | --- |
| `Eoln` | `undefined variable (Eoln)` | added |
| `soFromBeginning` / `soFromCurrent` / `soFromEnd` | undefined | added as aliases |
| `soBeginning` / `soCurrent` / `soEnd` | **already present**, Ord 0/1/2 | guarded |
| `TStringList.Sorted` + `Duplicates` | **already present and correct** — output matched FPC line for line, including `Add` landing in order, binary `IndexOf`, `dupIgnore`/`dupAccept`, and `Ord(dup*) = 0/1/2` | guarded |
| `IncMonth` | `undefined variable` | added |

**`Eoln`** (`lib/rtl/textfile.pas`) reuses the one-byte lookahead `Eof` already
parks in `f.Peek`, so it is non-destructive and shares a cursor with everything
else. FPC-measured, and the CR row is the one worth naming: `Eoln` answers True
at `#13` even though `TextReadChar` hands `#13` back as an ordinary character.
Both are FPC's behaviour, each measured on its own rather than inferred from the
other.

**`soFrom*`** are aliases of the existing enum values, not a second enum, so a
`Seek` written either way is the same call.

**`IncMonth`** (`lib/rtl/sysutils.pas`). The clamp is exactly what the ticket
warned it would be, and the case that catches a wrong implementation is `+2`
from the 31st: the clamp applies to the ORIGINAL day against the FINAL month, so
`IncMonth(2026-01-31, 2)` is **2026-03-31**, not the 2026-02-28 that clamping
month-by-month would give. Leap February, both directions, year rollover and
time-of-day preservation (including across a clamp) all measured against FPC.

Regression test: `test/lib_fpc_surface_2026_08.pas`, in `make lib-test` — the
guards on the two already-working items included, since "found working" is only
useful if it stays that way.


## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
