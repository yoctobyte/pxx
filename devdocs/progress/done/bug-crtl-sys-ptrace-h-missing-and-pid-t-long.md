---
slug: bug-crtl-sys-ptrace-h-missing-and-pid-t-long
track: C
prio: 60
type: bug
status: done
owner: rd
created: 2026-11-20
found-by: rainyday
tags: [crtl, headers, rainyday]
blocked-by: []
summary: "`#include <sys/types.h>` then `#include <sys/ptrace.h>` failed with a conflicting __pid_t typedef: crtl had no <sys/ptrace.h>, so the host's was reached and dragged in host <bits/types.h>, whose __pid_t is int while crtl's was long."
---

# <sys/ptrace.h> after <sys/types.h>: conflicting __pid_t

Reported by Rainyday: drivers/lib/confine_test.c called ptrace through
`syscall()` to avoid it. The repro is a .c file with `#include <sys/types.h>`
then `#include <sys/ptrace.h>`:
`error: conflicting types for typedef '__pid_t'`, in /usr/include/bits/types.h.

## Two bugs, both fixed

1. **crtl had no <sys/ptrace.h> and no ptrace().** The include fell through
   to the host's header (with the "resolved from the host system" warning)
   and from there to host <bits/types.h>. Added:
   - lib/crtl/include/sys/ptrace.h: glibc's interface, `enum
     __ptrace_request` with each name also a macro, the PTRACE_O_* options,
     the PTRACE_EVENT_* events, and a variadic `long ptrace(enum
     __ptrace_request, ...)`.
   - lib/crtl/src/sys/ptrace.c: glibc's PEEK convention. The word comes back
     as the return value with errno 0, so a peeked -1 is told from a failure
     by errno.
2. **crtl's `__pid_t` was `long`.** It must be `int`: pid_t is int (crtl's
   own <sys/types.h> says so at length), and so is glibc's `__pid_t`. That
   was the clash. It also meant termios.h's `__pid_t` prototypes did not
   match the `pid_t` definitions in src/termios.c, which the comment there
   claimed were "the same type".

## Measured

test/c_crtl_ptrace.c includes <sys/types.h> first, forks a child that does
PTRACE_TRACEME and stops itself, then has the parent PEEK a word, PEEK a
stored -1 (errno 0), PEEK a bad address (fails, errno set), POKE, re-PEEK,
CONT, read the exit status, and self-ATTACH (fails). Its output is identical
to gcc + glibc on x86-64 and on i386, and it compiles for aarch64. It is a
test-core row next to crypt_r. The termios tests (c_pty_family,
c_termios_no_tty, c_os_freebsd_termios) give the same output as before.
compiler/crtl_names.inc is regenerated (+ptrace:sys/ptrace.h).

Rainyday can drop the raw `syscall(SYS_ptrace, ...)` in confine_test.c once a
build with this is published.
