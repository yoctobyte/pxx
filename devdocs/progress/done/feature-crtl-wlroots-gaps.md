---
slug: feature-crtl-wlroots-gaps
track: C
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-27
closed: 2026-11-27
found-by: pxx2 (wlroots 0.20.2 replay for Panorama, tools/replay/compdb.py)
tags: [crtl, wlroots, panorama]
summary: "Replaying wlroots 0.20.2's 216 C units (with -std=gnu17 swapped in for the c23 they ask, as a measurement) left 6 failing on three crtl gaps, now fixed: F_DUPFD_CLOEXEC (and the Linux fcntl commands beside it: F_SETLEASE/GETLEASE/NOTIFY, F_SETPIPE_SZ/GETPIPE_SZ), shm_open/shm_unlink, and crtl's own netdb.c, which reached strcasecmp through <string.h> and so broke under a unit's _POSIX_C_SOURCE (the unit's flags compile the crtl sources it pulls in). 216/216 after. Test c_shmdup26 against gcc."
---

# crtl gaps wlroots found

From `tools/replay/compdb.py` over wlroots' `compile_commands.json`, with
`-std=gnu17` in place of `-std=c23` (pxx refused c23; that is
feature-c-std-c23): 210/216 compiled, the 6 failures three crtl gaps.

- **`F_DUPFD_CLOEXEC`** (POSIX.1-2008; Linux 1030): wlroots duplicates
  dmabuf and syncobj fds with it (render/dmabuf.c, render/egl.c,
  wlr_linux_drm_syncobj_v1.c). The fcntl() wrapper passes commands through, so
  only the constant was missing. Added with it, glibc's other Linux commands
  at the same base: F_SETLEASE, F_GETLEASE, F_NOTIFY, F_SETPIPE_SZ,
  F_GETPIPE_SZ. They are visible without _GNU_SOURCE (glibc hides them):
  POSIX reserves the F_ prefix for <fcntl.h>.
- **`shm_open` / `shm_unlink`** (POSIX shared memory; util/shm.c makes wl_shm
  pools with it): /dev/shm/NAME, leading slashes dropped, O_NOFOLLOW and
  O_CLOEXEC added; empty or slash-holding names EINVAL, past NAME_MAX
  ENAMETOOLONG, as glibc. "." and ".." go to open() as glibc lets them.
- **netdb.c's `strcasecmp`**: crtl's own source took it from <string.h>,
  which brings <strings.h> only when no standard is asked for. A unit
  compiled with `-D_POSIX_C_SOURCE=200809L` compiles the crtl sources it
  pulls in with that macro too, and the call was undeclared. netdb.c now
  includes <strings.h>.

Test c_shmdup26 (c_shm_open_dupfd.c, under _POSIX_C_SOURCE): the shm object
created, sized, mapped, reopened without its slash, EEXIST/ENOENT, the
name rules, close-on-exec on shm_open's fd and on F_DUPFD_CLOEXEC's copy and
not on F_DUPFD's; identical to gcc + glibc.
