# C: typedef return type can corrupt program entry call

- **Type:** bug
- **Status:** done
- **Track:** C frontend / crtl headers
- **Opened:** 2026-06-27
- **Closed:** 2026-06-27
- **Found-by:** Track B `crtl` socket wrapper work

## Symptom

A C function definition whose return type was `ssize_t` from
`#include <sys/types.h>` could compile but produce an executable whose entry path
segfaulted before `main` ran.

Original repro:

```c
#include <sys/types.h>

extern long ext_send(int, const void *, int);

ssize_t sendx(int fd, const void *buf, size_t len, int flags) {
  (void)flags;
  return (ssize_t)ext_send(fd, buf, (int)len);
}

int main(void) { return 42; }
```

Observed before the fix:

```text
ok: /tmp/bug_ssize_return
Segmentation fault (core dumped)
```

Re-verified 2026-06-27 audit: still open. Current `compiler/pascal26` built the
repro with `-Ilib/crtl/include`, but the resulting executable exited `139`
(`SIGSEGV`) before reaching the `return 42` path.

The same ABI spelled directly as `long sendx(...)` did not corrupt entry. The
`crtl` socket implementation therefore temporarily spelled the
`send`/`recv`/`sendto`/`recvfrom` definitions with direct `long` return types,
while the public headers declared the normal `ssize_t` surface.

## Cause

This was a CRTL header bug, not a scalar typedef codegen bug. Both
`lib/crtl/include/sys/types.h` and `lib/crtl/include/sys/_types.h` used the same
include guard, `PXX_CRTL_SYS_TYPES_H`. Including `<sys/types.h>` defined that
guard before it included `<sys/_types.h>`, so `_types.h` was skipped and
`__ssize_t` was never typedef'd.

The later `typedef __ssize_t ssize_t;` line therefore referenced an undefined
type name, and the C parser recovered poorly enough to produce a malformed
executable.

## Fix

`sys/_types.h` now uses its own include guard. `ssize_t` from `<sys/types.h>` is
therefore backed by `typedef long __ssize_t` as intended.

The `crtl` socket implementation now uses `ssize_t` for `send`, `recv`,
`sendto`, `recvfrom`, and the helper return type, removing the direct-`long`
workaround.

## Regression

Added `test/ctypedef_sys_ssize_b92.c`, wired into `make test-core`:

```c
#include <sys/types.h>

ssize_t f(void) { return 7; }
int main(void) { return f() == 7 ? 42 : 1; }
```

Focused checks:

- `test/ctypedef_sys_ssize_b92.c` returns `42`.
- A standalone `<sys/types.h>` `ssize_t` function repro returns `42`.
- The original repro no longer segfaults; it now reaches the expected dynamic
  loader error for its intentionally undefined `ext_send`.
- `test/csocket_loopback_b88.c` still returns `42` with the socket wrappers
  spelled as `ssize_t`.
