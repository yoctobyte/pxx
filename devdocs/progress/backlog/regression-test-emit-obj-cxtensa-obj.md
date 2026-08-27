---
prio: 70
track: C
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/cxtensa_obj.c@1 red at 32fba2082684 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T09:35:04Z
- **Test source:** test/cxtensa_obj.c

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/cxtensa_obj.c@1'` at 32fba2082684be424a045b5154c8ba3f7abea053

## Range
> **The named sha `32fba2082684` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `32fba2082684`, last good `457bda75412e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:350: error: undefined variable (SYS_openat)
pascal26:355: error: undefined variable (SYS_read)
pascal26:360: error: undefined variable (SYS_write)
pascal26:378: error: undefined variable (SYS_lseek)
pascal26:384: error: undefined variable (SYS_fsync)
pascal26:389: error: undefined variable (SYS_close)
pascal26:399: error: undefined variable (SYS_rt_sigaction)
pascal26:404: error: undefined variable (SYS_unlinkat)
pascal26:409: error: undefined variable (SYS_renameat)
pascal26:415: error: undefined variable (SYS_mkdirat)
pascal26:420: error: undefined variable (SYS_unlinkat)
pascal26:426: error: undefined variable (SYS_chdir)
(tail)
89035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_unlinkat >>>  PAL_AT_FDCWD  
pascal26:426: error: undefined variable (SYS_chdir)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_chdir >>>  Int64  
pascal26:436: error: undefined variable (SYS_symlinkat)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_symlinkat >>>  Int64  
pascal26:442: error: undefined variable (SYS_linkat)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_linkat >>>    
pascal26:448: error: undefined variable (SYS_ftruncate)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_ftruncate >>>  handle  
pascal26:455: error: undefined variable (SYS_faccessat)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_faccessat >>>  PAL_AT_FDCWD  
pascal26:460: error: undefined variable (SYS_fchown)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_fchown >>>  handle  
pascal26:465: error: undefined variable (SYS_geteuid)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_geteuid >>>    
pascal26:472: error: undefined variable (SYS_getuid)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_getuid >>>    
pascal26:477: error: undefined variable (SYS_getgid)
  in: /tmp/testmgr-scratch-2989035/compiler/../lib/rtl/platform/posix/platform_backend.pas
  near:  Integer  __pxxrawsyscall  SYS_getgid >>>    
pascal26: too many errors, stopping

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
