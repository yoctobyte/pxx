/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <execinfo.h>'s bodies.
 *
 * THE FRAMES ARE FOUND THROUGH THE FRAME-POINTER CHAIN, which every function
 * pxx compiles keeps: each frame's first word is the caller's frame pointer
 * and the next is the return address into the caller (x86-64 rbp, aarch64
 * x29, the same two-word record). glibc walks unwind tables
 * instead; for pxx's own code the two give the same addresses, from the
 * caller of backtrace() outwards. The chain ends at the process entry, whose
 * frame pointer is 0 (pxx --link's _start and pxxcrt both clear it).
 *
 * backtrace() is what a crash handler calls, so a walk that goes wrong must
 * STOP rather than fault: it ends at a frame pointer that does not move up
 * the stack, moves more than 16 MiB at once, or is not word-aligned -- the
 * shapes of code compiled without frame pointers, or of a thread whose first
 * frame inherited a register it never set.
 *
 * backtrace_symbols() has no symbol table to read (a static image with no
 * dynamic symbols, which is what glibc's dladdr also fails on), so each
 * string is glibc's form for an address it cannot name: "[0x...]". The
 * strings live in the same malloc block as the array, so one free() releases
 * both, as glibc documents.
 */
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int backtrace(void **buffer, int size) {
  /* backtrace's OWN frame pointer, read here rather than in a helper (a
     leaf helper may get no frame record of its own, and the walk would
     start one link off). NOT __builtin_frame_address(0): pxx lowers that to
     the address of a hidden local (enough for the stack-depth checks it
     serves), not to the frame register. Its first link's return address is
     in backtrace's caller, where glibc's list starts too. On a target
     without a known frame register the walk is empty, which the interface
     allows (backtrace may return 0). */
  void **fp = 0;
  int n = 0;
#if defined(__x86_64__)
  __asm__ volatile("mov %%rbp, %0" : "=r"(fp));
#elif defined(__aarch64__)
  __asm__ volatile("mov %0, x29" : "=r"(fp));
#endif
  while (fp && n < size) {
    void **next = (void **)fp[0];
    void *ret = fp[1];
    if (!ret) break;
    buffer[n++] = ret;
    if (next <= fp || (char *)next - (char *)fp > (16L << 20) ||
        ((unsigned long)next & (sizeof(void *) - 1)))
      break;
    fp = next;
  }
  return n;
}

#define PXX_BT_SYMLEN 24   /* "[0x" + 16 hex digits + "]" + NUL, rounded up */

char **backtrace_symbols(void *const *buffer, int size) {
  char **v;
  char *s;
  int i;
  if (size < 0) size = 0;
  v = malloc((unsigned long)size * (sizeof(char *) + PXX_BT_SYMLEN) + 1);
  if (!v) return 0;
  s = (char *)(v + size);
  for (i = 0; i < size; i++) {
    v[i] = s;
    snprintf(s, PXX_BT_SYMLEN, "[%p]", buffer[i]);
    s += PXX_BT_SYMLEN;
  }
  return v;
}

void backtrace_symbols_fd(void *const *buffer, int size, int fd) {
  char line[PXX_BT_SYMLEN + 1];
  int i, k;
  for (i = 0; i < size; i++) {
    k = snprintf(line, sizeof line, "[%p]\n", buffer[i]);
    if (k > 0) write(fd, line, (unsigned long)k);
  }
}
