---
title: Windows (experimental)
order: 62
---

# Windows (experimental)

`--os=windows` writes a Windows x64 console executable (PE32+) from Pascal,
C or Nil Python. It is **EXPERIMENTAL**, like every target except Linux. It
is single-threaded, and it cannot open sockets yet.

```sh
./pxx --os=windows hello.pas hello.exe     # run it on Windows, or: wine64 hello.exe
```

The program imports `kernel32.dll` and nothing else. It needs no C runtime
(msvcrt or ucrt) and no installer.

## How it works

The design is the same as the BSD targets (see
[FreeBSD and the BSDs](./freebsd.md)). The runtime is written against the
Linux system-call interface, and under `--os=windows` every system call goes
to a small translator compiled into the program
(`compiler/builtin/winabi.pas`). The translator answers it with kernel32
calls. Windows has no stable system-call numbers (they change between
builds), so kernel32 is the bottom layer rather than the kernel.

Four things differ from the BSD ports:

- **The file format.** `compiler/pewriter.inc` writes the PE image. It is
  laid out like the ELF one, with the code at RVA `0x1000` and the data
  after it. Imports go through the Import Address Table, which takes the
  place of the GOT slots the x86-64 external call already reads. The image
  loads at a fixed base (`0x400000`) with no relocations, so there is no
  ASLR yet.
- **The calling convention.** pxx code keeps the System V convention
  internally. Each call to a DLL function converts at the call site: the
  first four arguments move to `rcx`, `rdx`, `r8` and `r9`, the fifth and
  sixth go to the stack above 32 bytes of shadow space, and stacked
  arguments already land where Windows expects them. Floating-point
  arguments are not converted yet (Windows assigns `xmm0`–`xmm3` by
  position).
- **Thread-local storage.** A Windows program cannot point `fs` or `gs` at
  its own block, because `gs` is the thread environment block. In phase 1
  every thread-local access is therefore emitted as a rip-relative access
  to the main thread's block. That is why `--threadsafe` is refused.
- **The stack.** The image commits its whole 8 MiB stack at load time.
  Windows grows a stack one guard page at a time, and pxx functions do not
  probe their frames, so a frame larger than 4 KiB would otherwise skip the
  guard page and crash.

## What works

Each item is checked against the Linux build of the same test by `make
test-windows` (run under Wine through `tools/vm/wine.sh`):

- console output and input
- the heap
- exceptions
- time and `Sleep`
- command-line arguments (`ParamCount`/`ParamStr`, split by the Microsoft
  C runtime's quoting rules, and converted to UTF-8)
- environment variables
- exit codes and runtime errors
- files: open/create/truncate/append, read and write, seek,
  `pread`/`pwrite` and their vector forms, `stat`/`fstat`, rename, delete,
  `ftruncate`, `fsync`, `dup`/`dup2`, and pipes
- directories: create, remove, list (`getdents64` over `FindFirstFileW`),
  the current directory, and the `*at` calls relative to a directory fd

- `select`, `poll` and their `p` forms, on the console, pipes and files
- starting programs: `ExecuteProcess` and the other SysUtils process calls,
  and Nil Python's `subprocess` (`run`, `Popen`, pipes in both directions,
  return codes, `FileNotFoundError`), with `wait4` and `kill`

Windows has no `fork`, so the runtime's one spawn routine
(`PalBackendVforkAndExec3`) passes the whole request to the translator,
which calls `CreateProcessW` instead of forking and `exec`ing. The argument
list is quoted so that the child's C runtime splits it back into the same
strings. A program named without a path is looked up on `PATH` (separated by
`;`, with or without `.exe`), then by `CreateProcessW` itself. A child ended
by `kill` reports that signal to `wait`, as on Linux. A C program's own
`fork()` answers `ENOSYS`.

`select` and `poll` wait in a short sleep loop: Windows has no one call that
covers consoles, pipes and files.

Paths are converted from UTF-8 to UTF-16, and `/` works as a separator.
`/dev/null` becomes `NUL`. An absolute Unix path such as `/tmp/x` is taken
on the current drive. Under Wine that is drive `Z:`, the Unix root, so the
path means what it means on Linux.

## Not supported yet

- **Refused at compile time:** `--threadsafe`, `-g`, `--shared`,
  `--emit-obj`, `--rtl-libc`, and CPUs other than x86-64.
- **Not supported:** C's `fork()`, process groups, symbolic links, file
  modes (`chmod` succeeds and does nothing), and `mmap` of a file.
- **Phase 3:** exceptions from hardware faults (no vectored exception handler
  yet), threads (through the PE TLS directory), and sockets.
- **Calling other libraries:** `external 'libc.so.6'` and other Linux
  libraries cannot work on Windows. `external 'user32.dll'` and other DLLs
  do work, without floating-point arguments.

A system call the translator does not map returns `ENOSYS`. Set
`PXX_WINABI_TRACE=1` in the environment to have each one named on stderr.

The work log is in `devdocs/progress/working/feature-port-windows-pe.md`.
