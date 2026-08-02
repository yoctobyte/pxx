---
track: B
prio: 25
type: feature
---

# crtl gap batch: `chdir`, `dup`, `dup2`, `symlink`, `link`

- **Type:** feature (libraries) — **Track B** (`lib/crtl`)
- **Filed:** 2026-08-02 under [[feature-crtl-implement-libc-assumptions]], from
  the round-6 probe. Ranked as its own batch, per that collector's rule.

## Measured

Present and callable already: `rmdir`, `unlink`, `ftruncate`, `fsync`, `mkdir`,
`chmod`, `fchmod`, `umask`, `rename`, `remove`. Not declared:

| symbol | header | note |
| --- | --- | --- |
| `chdir` | unistd.h | also the last gap from the round-1 probe (47/48) |
| `dup` | unistd.h | |
| `dup2` | unistd.h | **`PalDup2` already exists** — bridge only |
| `symlink` | unistd.h | |
| `link` | unistd.h | |

## Cost is uneven, which is the useful part of this note

`dup2` is nearly free: `lib/rtl/platform.pas` already exports `PalDup2`
(`platform.pas:192`), so it needs a `__pxx_dup2` bridge in `lib/rtl/pxxcio.pas`
and a declaration. `dup` is `PalDup2`-adjacent but has no PAL entry of its own.

`chdir`, `symlink` and `link` need **new PAL surface** (syscall in the posix
backend, an honest `PAL_ERR_UNSUPPORTED` in the ESP one, plus the `__pxx_`
bridge). That is the same shape as `PalConnectUnix` added on 2026-08-02 — see
that commit for the pattern, including the i386 `socketcall`-style caveat that
some syscalls take a different path on 32-bit.

So this splits cleanly: do `dup2`/`dup` first for a cheap win, and treat the
three filesystem calls as the real work.

## A caution about `chdir`

It changes process-global state, and `lib/rtl` caches nothing about the working
directory today, so nothing in-tree should go stale. Worth confirming that
`PalGetcwd`'s callers do not memoise before adding it, since a stale cwd after a
`chdir` would be a silent wrong path rather than an error.

## Gate

A differential test against gcc per call, in the style of
`test/cstring_batch.c` — whole output diffed, no recorded expectations. `dup2`
proven by redirecting a real fd and reading it back; `symlink`/`link` by
creating one in `/tmp` and `stat`-ing both ends. Cross-check
i386/aarch64/arm32, since `lib/crtl` builds for every target while `gate.sh lib`
is x86-64 only ([[frank2-crtl-changes-need-cross-check]]).
