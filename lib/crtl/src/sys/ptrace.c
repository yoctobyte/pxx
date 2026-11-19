/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: ptrace(2), with glibc's PEEK convention.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c for
 * why (an undeclared SYS_ becomes 0 and the call lands on syscall zero).
 * syscall() has already turned -errno into -1 plus errno.
 */
#include <sys/ptrace.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <stdarg.h>

/* Variadic, as glibc's: pid, addr and data are read whatever the caller
 * passed (PTRACE_TRACEME callers pass zeros). The raw PEEK syscalls store the
 * word at *data; the library call RETURNS it instead, with errno 0, so the
 * wrapper points data at its own word. */
long ptrace(enum __ptrace_request request, ...)
{
  va_list ap;
  pid_t pid;
  void *addr, *data;
  long word, res;
  int peek;
  va_start(ap, request);
  pid = va_arg(ap, pid_t);
  addr = va_arg(ap, void *);
  data = va_arg(ap, void *);
  va_end(ap);
  peek = request == PTRACE_PEEKTEXT || request == PTRACE_PEEKDATA ||
         request == PTRACE_PEEKUSER;
  if (peek) data = &word;
#ifdef SYS_ptrace
  res = syscall(SYS_ptrace, (long)request, (long)pid, (long)addr, (long)data);
  if (res >= 0 && peek) {
    errno = 0;
    return word;
  }
  return res;
#else
  (void)pid; (void)addr; (void)data; (void)word; (void)res; (void)peek;
  errno = ENOSYS;
  return -1;
#endif
}
