# C stdio must ride pxx syscalls (libc-free), not import libc

- **Type:** library work (Track C — lib/crtl, C frontend builtins). NOT Track A.
- **Found:** 2026-06-26 getting pxx-compiled lua to RUN. Reframed after review:
  pxx does stdio via direct SYSCALLS (like Pascal), never libc. File/console IO
  must STAY libc-free. (Earlier "import libc stdout via COPY relocation" framing
  was WRONG — discard it.)

## State
- `printf` already works: the C frontend intercepts the name -> `AN_WRITE` (a
  write syscall, cparser.inc ~1230). No libc.
- `fwrite` / `fputs` / `fputc` / `puts` / `stdout` / `stderr` / `stdin` do NOT
  bridge — they fall through to the default libc.so.6 import. `stdout` is a libc
  DATA symbol pxx doesn't import, so it reads 0 and lua's `lua_writestring`
  (`fwrite(s,1,n,stdout)`) null-derefs. lua RUNS non-IO code; any output crashes.
- C cannot emit a raw syscall (`__asm__` unsupported), so the bridge must be a
  pxx intrinsic or a Pascal-backed helper.

## Fix — REUSE the existing Pascal RTL (do NOT rewrite IO)
KEY: C can import Pascal libraries, and the Pascal RTL already implements
file/console IO once, PAL-aware (posix syscalls / ESP-IDF). So C stdio is a thin
C-ABI VENEER that calls the EXISTING Pascal RTL IO routines — not a new
__pxx_write + a from-scratch stdio.c. No duplication, no second IO path.

- stdout/stderr/stdin -> map to the Pascal RTL's standard handles / fd 1,2,0.
- fwrite/fputs/fputc/puts/fread/fopen/fclose/fseek/fflush -> call the matching
  Pascal RTL routine (the one Pascal `write`/`Assign`/`BlockWrite`/file API
  already uses), which already dispatches through the PAL (posix vs ESP-IDF).
- The earlier "__pxx_write builtin + lib/crtl/src/stdio.c from scratch" plan is
  superseded by this: only write the veneer + the C<->Pascal RTL binding. printf
  staying on AN_WRITE is fine, or also re-point it at the RTL for consistency.

## (superseded) earlier from-scratch sketch
1. Add a low-level syscall bridge usable from C: a `__pxx_write(int fd, const
   void *buf, unsigned long len)` builtin that emits the write syscall (reuse the
   AN_WRITE / AN_SYSCALL path the printf stub already uses). Likewise
   `__pxx_read` for input. ESP/cross go through the PAL, same as Pascal.
2. lib/crtl/src/stdio.c: define `FILE` so `stdout`/`stderr`/`stdin` are real
   objects carrying fd 1/2/0; implement `fwrite`/`fputs`/`fputc`/`putchar`/
   `puts`/`fflush`/`fread`/`fopen`/`fclose`/`fseek` on `__pxx_write`/`__pxx_read`
   + the open/close/lseek syscalls. Compile it into the program (amalgamation),
   so these resolve INTERNALLY — no libc.so.6 import for IO.
3. Abstraction (IMPORTANT): C stdio is a thin C-ABI veneer over the PAL, NOT a
   fork and NOT hardcoded syscalls. The PAL backend decides the mechanism:
   - posix (x86-64/linux): raw write/read/open/lseek syscalls.
   - ESP32: route through ESP-IDF (assume IDF for now; IDF provides
     vfs/console/fatfs). stdio without IDF is possible but out of scope.
   So __pxx_write etc. dispatch to the active PAL (PXX_PLATFORM_*), exactly like
   Pascal's IO already does — C and Pascal share ONE platform IO layer.

Last run blockers after this: bug-c-double-vararg (%f in number formatting),
global ARRAY initializer data (lua's static luaL_Reg tables).
