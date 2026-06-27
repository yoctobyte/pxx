# Re-pin stable for C stdio/socket PAL bridge

- **Type:** chore
- **Status:** backlog
- **Track:** A/C handoff, affects Track B `lib/crtl` gates
- **Opened:** 2026-06-27
- **Found-by:** Track B `crtl` work, after implementing `bug-c-crtl-fopen-missing`

## Problem

The pinned Track B compiler (`stable_linux_amd64/default/pinned`, currently
stable v81) self-hosts cleanly, but it cannot run the new `crtl` PAL-bridge
regressions as pinned gates yet.

File stdio:

```sh
stable_linux_amd64/default/pinned \
  -Ilib/crtl/include -Ilib/crtl/src \
  test/cfile_stdio_b87.c /tmp/cfile_stdio_b87_pinned
/tmp/cfile_stdio_b87_pinned
```

The compile succeeds, but the executable fails at load time:

```text
symbol lookup error: /tmp/cfile_stdio_b87_pinned: undefined symbol: __pxx_write
```

Sockets show the same pin lag:

```sh
stable_linux_amd64/default/pinned \
  -Ilib/crtl/include -Ilib/crtl/src \
  test/csocket_loopback_b88.c /tmp/csocket_loopback_b88_pinned
/tmp/csocket_loopback_b88_pinned
```

The compile succeeds, but the executable fails at load time:

```text
symbol lookup error: /tmp/csocket_loopback_b88_pinned: undefined symbol: __pxx_socket
```

This is not a `crtl` body failure. A compiler generated from the current source
by the pinned compiler resolves the Pascal-backed `pxxcio` bridge correctly:

```sh
stable_linux_amd64/default/pinned compiler/compiler.pas /tmp/pxx-sc-g1
/tmp/pxx-sc-g1 -Ilib/crtl/include -Ilib/crtl/src \
  test/cfile_stdio_b87.c /tmp/cfile_stdio_b87_g1
/tmp/cfile_stdio_b87_g1   # returns 42
```

`make selfcheck` is also green with pinned:

```text
self-host fixedpoint OK (g2 == g3)
=== selfcheck OK ===
```

## Acceptance

- Re-pin stable so `stable_linux_amd64/default/pinned` includes the C driver
  behavior that auto-pulls/binds `lib/rtl/pxxcio.pas` for C programs.
- The pinned compiler can compile and run `test/cfile_stdio_b87.c`, returning 42.
- The pinned compiler can compile and run `test/csocket_loopback_b88.c`,
  returning 42.
- If the regression is kept in `make test-core`, the checked-in
  `compiler/pascal26` seed and/or pinned Track B flow should be consistent with
  that gate.

## Log

- 2026-06-27 — Filed from Track B `crtl` fopen work. Current generated compiler
  passes the regression; pinned v81 compiles it but produces a runtime unresolved
  `__pxx_write`.
- 2026-06-27 — Extended from Track B `crtl` socket work. Current generated
  compiler passes `test/csocket_loopback_b88.c`; pinned v81 compiles it but
  produces a runtime unresolved `__pxx_socket`.
