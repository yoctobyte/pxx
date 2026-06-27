# C: typedef return type can corrupt program entry call

- **Type:** bug
- **Status:** backlog
- **Track:** C frontend / codegen
- **Opened:** 2026-06-27
- **Found-by:** Track B `crtl` socket wrapper work

## Symptom

A C function definition whose return type is a typedef of `long` can compile but
produce an executable whose entry stub calls one byte before the entry code,
segfaulting before `main` runs.

Repro:

```c
#include <sys/types.h>

extern long ext_send(int, const void *, int);

ssize_t sendx(int fd, const void *buf, size_t len, int flags) {
  (void)flags;
  return (ssize_t)ext_send(fd, buf, (int)len);
}

int main(void) { return 42; }
```

Observed with a compiler generated from current source:

```text
ok: /tmp/bug_ssize_return
Segmentation fault (core dumped)
```

Re-verified 2026-06-27 audit: still open. Current `compiler/pascal26` builds the
repro with `-Ilib/crtl/include`, but the resulting executable exits `139`
(`SIGSEGV`) before reaching the `return 42` path.

The same ABI spelled directly as `long sendx(...)` runs correctly. The `crtl`
socket implementation therefore spells the `send`/`recv`/`sendto`/`recvfrom`
definitions with direct `long` return types, while the public headers can still
declare the normal `ssize_t` surface.

## Acceptance

- The repro above returns 42.
- The `crtl` socket wrappers can use `ssize_t` as the implementation return
  spelling without corrupting the entry stub.

## Log

- 2026-06-27 — Filed from `lib/crtl/src/socket.c`; workaround is direct `long`
  return spelling in implementation definitions.
