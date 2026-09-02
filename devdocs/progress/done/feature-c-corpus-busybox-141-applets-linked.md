---
track: C
prio: 70
type: feature
status: done
created: 2026-09-02
found-by: frankD
owner: frankD
blocked-by: []
summary: "Rung 3: the 141-applet busybox userland, one object per translation unit, one real link -- what feature-c-corpus-busybox-userland-by-separate-compilation deferred when it met its bar at 26 applets and 82 TUs. MET 2026-09-02: 265 objects linked separately, no -Wl,-z,muldefs, and the 109MB result is BYTE-IDENTICAL to the gcc oracle over 387 cases, with the gcc build itself agreeing with upstream. Started at 260 of 265 compiling and a link that failed. Every gap was found by ATTEMPTING the target, never by triaging: a C frontend parse bug (a parameter written with FUNCTION type went down a different parser from the pointer spelling and its list was left unconsumed), an IR fold that looked at the wrong node (`x and 0' under the frontend's unsigned width mask, which kept a dead arm's call as a real external reference), and the crtl surface 141 applets ask for -- sigprocmask/sigtimedwait/sigwait, wait4/wait3, sysinfo, the tty ioctls, net/ethernet.h, caddr_t, getnameinfo, a REAL numeric getaddrinfo, and the three HAVE_* entries busybox assumes without a guard. Filed rather than fixed: crtl has no pty family."
---

# Rung 3 — 141 applets, separately compiled, really linked

`feature-c-corpus-busybox-userland-by-separate-compilation` met its bar at 26
applets / 82 translation units and said in its own summary that **growing the
applet set past 26 is rung 3's business**. This is that.

## The bar

`tools/busybox_diff.sh --separate --applets "$(busybox --list)"` — 141 applets,
265 translation units, 265 objects, one real link with no `-Wl,-z,muldefs`,
and the result byte-identical to the gcc oracle over its case set.

x86-64 only. aarch64 stays out until `--emit-obj` has an object writer for it;
that is not this ticket's to fix.

## Met

```
  ORACLE  gcc separate build, 265 objects (387 cases)
  ORACLE  busybox agrees with the gcc build
  note    x86_64   265 objects linked separately (109131728 bytes)
  PASS    x86_64   byte-identical to the gcc oracle over 387 cases
busybox-diff: GREEN
```

compiler sha256 `084935c11df1f9d0`. See `devdocs/progress/LOGBOOK.md`
2026-09-02 for the two compiler defects and the crtl surface, each with its
own measurement.

**The last symbol was not a missing function.** After `getnameinfo` landed,
all 265 objects compiled and the link still failed on one name --
`data_extract_to_command`, from `if (opt & OPT_2COMMAND)` in `archival/tar.c`,
where the config sets that enum member to 0 and leaves the defining
translation unit out of the build. The dead arm survived because the `x and 0`
branch identity looked at the outer node of `and(and(opt,0),0xFFFFFFFF)` -- the
frontend's own unsigned width mask. A compiler fold, reached by attempting a
link.

## Log
- 2026-09-02 — resolved.

## Not in this rung

- The 141 applets this tree's `.config` selects. `su`, `login` and `passwd`
  want `-lcrypt` or `CONFIG_USE_BB_CRYPT`; `who` wants `FEATURE_UTMP`. Those
  are configuration, not pxx defects, and they are named here so the next
  person does not rediscover them as bugs.
- `libbb/getpty.c` is not in this set, which is why the missing pty family is
  filed (`feature-c-crtl-has-no-pty-family-at-all`) rather than blocking.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
