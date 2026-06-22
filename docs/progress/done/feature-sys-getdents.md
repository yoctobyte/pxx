# Directory scanning support — sys_getdents64 (libc-free)

- **Type:** feature
- **Status:** done
- **Owner:** — (lock released; last worked by Codex)
- **Opened:** 2026-06-21
- **Relation:** Stresses low-level syscall wrappers, pointer arithmetic, and type casting in RTL. Blocker for feature-demo-file-browser.

## Goal

Provide a statically-linked, libc-free directory scanning mechanism in the RTL using raw Linux system calls (`sys_getdents64`).

## Surface (sketch)

In `lib/rtl/platform.pas` (or per-platform files):
- Define standard constants and records (`linux_dirent64`).
- Wrap the raw system call `sys_getdents64` (Syscall 217 on x86-64).

In `lib/rtl/sysutils.pas`:
- `type TFileInfo = record Name: AnsiString; IsDir: Boolean; Size: Int64; end;`
- `type TFileInfoArray = array of TFileInfo;`
- `function GetDirectoryContents(const path: AnsiString; var list: TFileInfoArray): Boolean;`

## Implementation Steps

1. Expose `sys_getdents64` in `lib/rtl/platform.pas` for the different target architectures (x86_64, i386, aarch64, arm32).
2. Open directory file descriptor using `sys_open` with `O_RDONLY | O_DIRECTORY`.
3. Loop over `sys_getdents64` with a local buffer (e.g. 4096 bytes) and decode the variable-length `linux_dirent64` structures using pointer offsets.
4. Filter out `.` and `..` directory links.
5. Close the descriptor and return the parsed `TFileInfo` records.

## Log
- 2026-06-21 — Opened.
- 2026-06-21 — First Track B slice in progress: added PAL
  `PalGetDents64`, POSIX syscall numbers, ESP unsupported stub, and
  `SysUtils.GetDirectoryContents`. Regression `test/lib_directory.pas` covers
  one file plus one child directory on the POSIX backend. File size/metadata is
  still missing and split to `feature-pal-file-stat-metadata`.

- 2026-06-21 — HALTED → `unfinished/`. `working/` lock released (no active agent). In-flight code committed as 9f22df5 (sys_getdents64 + GetDirectoryContents + test); resume from there. Follow-up: feature-pal-file-stat-metadata.
- 2026-06-22 — DONE in this commit. Re-audited current state after
  `feature-pal-file-stat-metadata`: POSIX PAL exposes `PalGetDents64` and
  `PalStatAt`, `SysUtils.GetDirectoryContents` filters `.`/`..` and fills
  directory/file metadata, and `test/lib_directory.pas` covers entries, type,
  size, and stat. Verified with `make lib-test`.
