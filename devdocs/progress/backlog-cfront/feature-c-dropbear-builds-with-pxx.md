---
track: C
tags: [C, realworld]
prio: 40
type: feature
blocked-by: []
summary: "Build the dropbear SSH server (and dbclient, dropbearkey) with pxx from unmodified upstream sources, and prove it by logging in with a stock OpenSSH client. Real-world C after busybox/lua/sqlite: ~90k lines with bundled libtomcrypt/libtommath, so crypto and bignum code that catches miscompiles no unit test does. Then it runs on gibux (instead of Alpine's gcc-built one) and on the BSD targets (--os=freebsd/netbsd/openbsd) as an end-to-end test of the translators."
status: open
owner: unassigned
---

# dropbear builds with pxx

Opened 2026-11-13 at the owner's request. Nobody has ever compiled dropbear
with pxx: gibux runs Alpine's prebuilt (gcc, musl) dropbear, and gibux's
`docs/design.md` names "build dropbear with pxx" as a pxx ticket that was
never filed. This is that ticket.

## Why dropbear

- The next real-world C program after busybox, lua and sqlite (see
  [[idea-c-realworld-test-targets]]): about 90k lines including its bundled
  libtomcrypt (ciphers, hashes, signatures) and libtommath (bignums). Crypto
  and multi-precision arithmetic exercise integer codegen, shifts, carries,
  64-bit multiplies and big stack frames in ways synthetic tests do not.
- **The verdict is unambiguous.** If a stock OpenSSH client can log in, run a
  command and copy a file, then key exchange, every negotiated cipher/MAC,
  host-key signatures and the bignum code were compiled correctly. A
  miscompile shows up as a failed handshake or a bad signature, not as a
  subtle wrong number.
- It is what a minimal distro, gibux, and the planned multi-kernel live image
  need for remote access.

## Rules (the same as for gibux and busybox)

- GCC is the reference: a gcc build of the same sources and configuration is
  the behaviour pxx must match.
- **No patches to dropbear.** Where pxx lacks something, pxx gains it (a
  ticket per gap, as busybox and sqlite did). Configuration choices dropbear
  itself offers (`localoptions.h`, `configure` flags) are fine.
- Pin one upstream release (the current stable dropbear, recorded with its
  sha256), as `tools/busybox_diff.sh --pinned` does for busybox 1.36.1.

## Expected snags (check, do not assume)

- **Build route.** dropbear's build is autoconf `configure` + make. Either
  make pxx pass as `CC` for configure (it probes with tiny test programs), or
  follow busybox's route: a unity build driven by a script under `tools/`
  (see `tools/busybox_diff.sh`, `tools/busybox_cat_unity.c`), with a
  `config.h` generated once by a gcc configure run. The unity route is the
  quicker first trophy; configure acceptance is worth its own ticket.
- **`__int128`.** pxx has none (no hit in compiler/ or lib/crtl).
  libtommath picks 64-bit digits with a 128-bit `mp_word` when the compiler
  advertises it (`__SIZEOF_INT128__`). If pxx does not define that macro,
  libtommath should fall back to its 32-bit digit configuration (`MP_32BIT`)
  by itself; verify. Implementing `__int128` is a separate, larger feature;
  do not block on it.
- **crtl surface** dropbear needs: ptys (`openpty` or `posix_openpt`/
  `grantpt`/`unlockpt`/`ptsname`), `crypt` and `getspnam` (shadow passwords),
  `syslog`, `getpwnam`, `initgroups`/`setgroups`, `fork`/`setsid`, `select`,
  `waitpid`, utmp/wtmp (can be configured off), `getrandom`/`/dev/urandom`.
  Start with zlib compression off (`--disable-zlib`).
- Password auth needs a real shadow-file check; public-key auth only needs
  file reads. Public-key login is the easier first test.

## Acceptance

1. `dropbear`, `dbclient` and `dropbearkey` build with pxx for x86-64 Linux
   from the pinned, unmodified sources (and the same configuration builds
   with gcc).
2. `dropbearkey` generates ed25519 and RSA host keys; a stock OpenSSH client
   logs in to the pxx-built `dropbear` with a public key, runs a command,
   gets an interactive pty session, and copies a file with `scp` (needs
   dropbear's scp built too, or the host's scp over dropbear's exec).
3. The pxx-built `dbclient` logs in to a stock OpenSSH server.
4. A repeatable test target (a `tools/` script and/or a Makefile target,
   not in the default `test`: it needs a download) running steps 2 and 3 on
   localhost with throwaway keys and a non-privileged port.
5. Then aarch64 (under qemu-aarch64), as busybox did.

## Follow-ups (other sessions)

- gibux: replace Alpine's dropbear with the pxx-built one (gibux session).
- BSD targets: the kernel-port session adds the pxx-built dropbear to
  `make test-freebsd`/`test-netbsd`/`test-openbsd` (ptys, sockets, fork and
  signals through every translator at once). Contact: the session working
  [[feature-port-libc-family-openbsd-netbsd-minix]].
