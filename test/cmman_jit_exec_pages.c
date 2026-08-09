/* SPDX-License-Identifier: Zlib */
/*
 * Anonymous mmap must give REAL pages, and mprotect must really flip them to
 * executable — the JIT shape: map RW, write machine code, mprotect R+X, call it.
 *
 * Both were no-op stubs (mmap returned MAP_FAILED, mprotect returned 0 without
 * doing anything), which was honest only while nothing was ever really mapped.
 * tcc -run needs this and could not work without it
 * (feature-crtl-implement-libc-assumptions, corpus step 3).
 *
 * FILE-BACKED mmap is still refused with MAP_FAILED on purpose: sqlite is the
 * only in-tree caller, its mmap I/O is off by default, and it falls back to
 * read/write. A wrong file mapping would be a silent data bug; a refusal is a
 * fallback.
 *
 * Exit code only — a printf bug must not be able to masquerade as a JIT bug.
 */

#include <sys/mman.h>
#include <string.h>

int main(void) {
  unsigned char code[] = { 0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3 };  /* mov eax,42; ret */
  void *p = mmap(0, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
  if (p == MAP_FAILED) return 1;
  memcpy(p, code, sizeof code);
  if (mprotect(p, 4096, PROT_READ|PROT_EXEC) != 0) return 2;
  int (*fn)(void) = (int(*)(void))p;
  if (fn() != 42) return 3;
  if (munmap(p, 4096) != 0) return 4;
  return 42;
}
