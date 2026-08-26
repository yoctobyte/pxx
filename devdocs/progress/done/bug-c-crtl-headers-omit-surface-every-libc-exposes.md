---
slug: bug-c-crtl-headers-omit-surface-every-libc-exposes
title: "crtl's C headers omit type and macro surface every libc exposes, so real C does not compile"
track: C
prio: 55
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
summary: "Four omissions in pxx's own C headers, all found by one busybox 1.37.0 sweep and all the same shape — a TYPE or MACRO that every libc puts in a specific header, absent from crtl's copy of that header, so code that includes the right header still fails. <sys/ioctl.h> had no _IOC family; <string.h> did not pull <strings.h> under __USE_MISC; <stddef.h> had no wchar_t; <wchar.h> had no mbstate_t. Together these were blocking 10 busybox files and every remaining non-library gap in the sweep."
---

# Four header omissions, one shape

Found compiling busybox 1.37.0. After the compiler fixes landed this session
([[feature-c-gnu-omitted-middle-conditional-elvis]],
[[bug-c-a-ternary-cannot-be-the-callee-of-a-call]],
[[bug-c-logical-not-is-not-folded-in-a-constant-expression]],
[[feature-c-gcc-extended-inline-asm]]), the sweep's remaining non-library
failures all turned out NOT to be compiler bugs. They were header gaps, and
grouping them is the point: each one is a type or macro that every libc places
in a particular header, missing from crtl's copy of that header. Code that
includes exactly the right header still fails, and the diagnostic lands far
from the cause.

## The four

**1. `<sys/ioctl.h>` had no `_IOC` family.** glibc reaches `_IO`/`_IOR`/`_IOW`/
`_IOWR` through `<bits/ioctls.h>` -> `<asm/ioctl.h>`. Real programs spell their
own ioctl numbers with them rather than including a `linux/` uapi header —
busybox writes `#define FDGETPRM _IOR(2, 0x04, struct floppy_struct)` and
`_IOW(BTRFS_IOCTL_MAGIC, 9, int)` in its own sources. Undefined, the macro name
survives preprocessing as a *call with a TYPE for an argument*, which is not a
C expression at all:

```
pascal26:82: error: expected C expression
  near: _IOR      >>>  floppy_struct
```

Blocked `libbb/copy_file.c`, `util-linux/fdformat.c`, `util-linux/rtcwake.c`.

**2. `<string.h>` did not pull in `<strings.h>`.** glibc does, under
`__USE_MISC`. busybox's `libbb.h` includes `<string.h>` and never
`<strings.h>`, and `strcasecmp`/`strncasecmp` were the single largest cause of
`call to undeclared function` in the sweep — 7 files.

**3. `<stddef.h>` had no `wchar_t`.** C99 7.17 puts it there; `<wchar.h>` is for
the wide-string *functions*. crtl had the typedef only in `<wchar.h>`, so
`libbb/lineedit.c` read it as `stray token at top level (not a declaration):
'wchar_t'`.

**4. `<wchar.h>` had no `mbstate_t`.** C99 7.24.1. Code that *implements* the
multibyte conversions — busybox defines its own `wcrtomb`/`wcstombs` — needs
the type only to name a parameter it then ignores. Without it the parameter
list mis-parsed and the function body reached IR lowering as a bare integer
literal:

```
pascal26:124: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 1)
```

Blocked `libbb/unicode.c` and `util-linux/rev.c`.

## What was deliberately NOT done

The `<string.h>` -> `<strings.h>` include is **gated** on
`_GNU_SOURCE`/`_DEFAULT_SOURCE`/`_BSD_SOURCE`, exactly as glibc gates it, and
for glibc's reason: `<strings.h>` defines `index()`, and `index` is an
extremely common local variable name. A strict-ISO translation unit must not
acquire that name just because it asked for `<string.h>`. Both directions are
tested.

`_IOC_TYPECHECK` is the user-space spelling, `(sizeof(t))`. The kernel's
variant compares `sizeof(t)` against `sizeof(t[1])` to provoke an error when
`t` is not a type; that arm is `#ifdef __KERNEL__` and yields the identical
value here.

No `wcrtomb`/`mbstowcs`/`mbrtowc` **implementations** were added. busybox
supplies its own; what was missing was the type, and adding function bodies
nobody asked for is scope this ticket does not have. `<wchar.h>` still declares
only `wcslen`/`towlower`/`towupper`.

## Outcome

Four header edits, no compiler change: `<sys/ioctl.h>` gains the asm-generic
`_IOC` family (the layout every target pxx builds for uses — only mips, alpha,
sparc, parisc and powerpc differ, and pxx targets none of them);
`<string.h>` gains a gated `#include <strings.h>`; `<stddef.h>` gains a guarded
`wchar_t`; `<wchar.h>` gains `mbstate_t` and defers its own `wchar_t` to the
same guard.

Four tests, all wired into `test-core`, all oracled byte-for-byte against
`gcc -O0`: `test/ccrtl_ioctl_macros.c` (both busybox call sites verbatim, all
five constructors, the four decoders, and that the size field really is the
type's size), `test/ccrtl_string_pulls_strings.c`,
`test/ccrtl_string_strict_iso.c` (the gate holding the OTHER way — a local
named `index` must still compile), `test/ccrtl_wchar_types.c` (whose
`<wchar.h>` include sits mid-file so the part above it proves the
`<stddef.h>` claim).

Gates: c-conformance 220/0, pascal-conformance 346/0/170/34, both unchanged.
`gate.sh quick` GREEN.

## What this measured

busybox 1.37.0, the 286 files gcc actually builds standalone: **178 -> 187**
clean. More useful than the count: every one of the 99 remaining failures is
now missing crtl *library* surface — functions (`strchrnul`, the `*_unlocked`
family, `getline`, `fseeko`, `dprintf`, `lchown`, ...) and the getopt globals
(`optind` accounts for the four `undeclared identifier passed as argument`
rows) — plus one policy question,
[[decide-c-crtl-rand-max-is-conforming-but-breaks-real-code]].

**No compiler defect remains in the sweep.** The eight that were open this
morning are closed: four were real frontend bugs and are fixed, four were
these header gaps wearing a compiler bug's diagnostic.


## Log
- 2026-08-26 — resolved, commit ebc01b2b9.
