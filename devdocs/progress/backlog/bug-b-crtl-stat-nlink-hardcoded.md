---
track: B
prio: 30
type: bug
---

# `struct stat.st_nlink` is hardcoded to 1

- **Type:** bug (crtl, wrong value) — **Track B** (`lib/crtl/src/sys/stat.c`)
- **Found:** 2026-08-02 while adding `link()`
  ([[feature-crtl-process-file-ops-batch]]) — the obvious way to prove a hard
  link exists is that the target's link count became 2, and it did not.

## Measured

```c
link("/tmp/f", "/tmp/g");
stat("/tmp/g", &st);
```

| | `st_nlink` |
| --- | --- |
| gcc | **2** |
| pxx | 1 |

`lib/crtl/src/sys/stat.c:35` assigns `buf->st_nlink = 1;` unconditionally. The
field is declared in the header, so code reads it and gets a plausible answer
that happens to be right only for the common case of an unlinked regular file.

The PAL does not carry the value at all — `TPalFileStat` has no `Nlink` — so
this is not a wiring slip in crtl, it is a field that was never plumbed.

## Why it matters

`st_nlink` is not decoration:

- **hard-link detection** — backup, dedup and archiving tools use `st_nlink > 1`
  to avoid storing the same inode twice, and with a constant 1 they silently
  store duplicates;
- **directory traversal shortcuts** — the classic `nlink - 2 == subdir count`
  optimisation makes `find`-shaped code skip real subdirectories;
- `rm`/`mv`-style safety checks that refuse to unlink a multiply-linked file.

Wrong in the direction that makes callers do *less* work than they should,
silently.

## Fix shape

Add `Nlink` to `TPalFileStat`, fill it from `statx`'s `stx_nlink` in the posix
backend (the syscall already returns it — `PAL_STATX_BASIC_STATS` includes
`STATX_NLINK`, so no extra request mask is needed), report it honestly on ESP,
and read it in `lib/crtl/src/sys/stat.c` instead of assigning 1.

Worth checking the other `struct stat` fields in the same pass for the same
shape — this one was found by accident, not by looking, and a hardcoded field
is invisible until something depends on it. `st_ino`, `st_dev`, `st_blocks`,
`st_blksize` and the uid/gid pair are the candidates.

## Gate

`link()` making the target's `st_nlink` 2 and `unlink` bringing it back to 1,
diffed against gcc; a directory's `st_nlink` matching gcc's for a directory with
known subdirectories. Cross-target, since `lib/crtl` builds for every target.
