# PAL file stat metadata

- **Type:** feature
- **Track:** B
- **Status:** done
- **Owner:** Codex
- **Opened:** 2026-06-21
- **Relation:** Follow-up from `feature-sys-getdents`; blocks full compact/tile
  metadata in `feature-demo-file-browser`.

## Problem

`SysUtils.GetDirectoryContents` can now return entry names and directory flags
from `getdents64`, but it cannot report file sizes or timestamps. The file
browser therefore renders names and `[D]` markers only; its compact view cannot
show size/date and preview code cannot cheaply decide file classes from metadata.

## Direction

- Add a PAL stat surface, preferably `PalStatAt`/`PalFStatAt` or `statx`, with
  POSIX raw-syscall backing and unsupported stubs for platforms without it.
- Expose at least size, mode/type, and modification time in an RTL-friendly
  record.
- Thread size into `TFileInfo.Size` instead of the current `-1` placeholder.

## Acceptance

- A library regression creates a file of known size and a directory, stats both,
  and verifies size/type through the PAL/SysUtils layer.
- `examples/fm/fm.pas` compact output can show a deterministic file size column.

## Log
- 2026-06-21 — Opened while implementing the first file-browser/getdents slice.
- 2026-06-21 — Claimed as part of the resumed PAL slice. Source now exposes
  `TPalFileStat`, `PalStat`, and `PalStatAt`; POSIX uses Linux `statx`, ESP
  returns unsupported with cleared output, and `SysUtils.GetDirectoryContents`
  fills size/type/mtime when metadata is available.
- 2026-06-21 — Validation with pinned compiler v32: `tools/library_suite.sh
  green` and `make lib-test` both pass. `test/lib_directory.pas` now checks
  directory-list file size plus direct `PalStat` file/dir metadata.
- 2026-06-22 — DONE. Commit pending in uncommitted working tree. Regression:
  pinned v32 `tools/library_suite.sh green`, `make lib-test`, and
  `tools/progress.sh check`.
