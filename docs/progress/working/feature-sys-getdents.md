# Directory scanning support — sys_getdents64 (libc-free)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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
