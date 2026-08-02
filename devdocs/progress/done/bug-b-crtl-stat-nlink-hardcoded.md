---
track: B
prio: 30
type: bug
status: done
owner: claude-B
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

## Resolved 2026-08-02 (commit c19f4d9b1) — and it was four fields, not one

The audit this ticket asked for ("worth checking the other `struct stat` fields
in the same pass") found three more, all hardcoded in `fill()`:

| field | was | now |
| --- | --- | --- |
| `st_nlink` | `1` | real |
| `st_uid` / `st_gid` | `0` | real |
| `st_rdev` | `0` | real |
| `st_atime` / `st_ctime` | **both assigned `mtime`** | real |

The timestamps are the one that would have been missed by fixing only what this
ticket named. All three of atime/mtime/ctime carried the same value, so any code
comparing access against modification time saw them equal — always, silently.
`st_dev`, `st_ino`, `st_size`, `st_blocks` and `st_blksize` were already real.

**No new syscall work was needed.** `statx` already returns every one of these
(`PAL_STATX_BASIC_STATS` covers them); `TPalFileStat` simply never carried them
and `fill()` substituted constants. Widened the PAL record, the C-side
`struct __pxx_statbuf` and its Pascal mirror `TPxxStatBuf` — **appending** in
each case, because that layout is an ABI shared between `pxxcio.pas` and
`lib/crtl/src/sys/stat.c` and the two must stay in step; appending leaves every
existing offset untouched.

The ESP backend reports the new fields as its `ClearPalFileStat` defaults, which
is honest: it has no stat syscall at all and already returns
`PAL_ERR_UNSUPPORTED`.

### Verified through consequences, not presence

`test/cstat_fields.c` asserts what the fields MEAN: `nlink` rises to 2 when a
hard link is created and falls back when it is removed, both names share an
inode, a directory's `nlink` counts its subdirectory (3, not 2), the uid matches
`geteuid()` and is non-zero, and all three timestamps are populated. Identical
to gcc on x86-64, i386, aarch64 and arm32.

A test asserting merely "st_nlink == 1 for a new file" would have passed against
the bug, which is why every assertion here moves a value.

### Noted, not worked around

`getuid` is not declared in crtl (`geteuid` is). The test uses `geteuid` and
says so rather than quietly picking the one that happens to exist — it belongs
with the other `unistd.h` gaps.

## Log
- 2026-08-02 — resolved, commit PENDING.
