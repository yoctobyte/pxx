---
slug: bug-n-a-bare-import-of-a-c-header-only-name-builds-a-binary-that-cannot-exec
track: N
prio: 50
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankZ
blocked-by: [feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym]
tags: [nilpy, imports, ffi, soname, silent]
summary: "`import strings` in a .npy resolves to /usr/include/strings.h, synthesises `libstrings.so` from the header's own file NAME, and emits a DT_NEEDED no loader can satisfy. Verified against the PINNED compiler (2026-09-10): the build succeeds, `readelf -d` shows `Shared library: [libstrings.so]`, and the program dies at exec with `cannot open shared object file`. At HEAD it is a compile error instead, because e53eff428's guard catches exactly this -- so the OBSERVABLE has already moved from silent-broken-binary to loud-refusal, and this row is about the remaining half: nothing should have emitted that DT_NEEDED in the first place. NOT a resolution bug: `strings` is DELIBERATELY absent from pasparser_proc.inc's curated bare-import list (an ordinary Pascal unit sharing a Python name, named there beside `classes` and `types`), so falling through to the host header is the documented behaviour. Six of the seven RTL/header name collisions on this box -- math, menu, netdb, png, regex, zlib -- resolve to the unit; `strings` is the one that reaches a header, which is why nobody hit this before."
---

# Measured 2026-09-10

```
$ ./stable_linux_amd64/default/pinned  <<< 'import strings' + print
ok: .../imps2
$ readelf -d imps2 | grep NEEDED
 0x0000000000000001 (NEEDED)   Shared library: [libstrings.so]
$ ./imps2
error while loading shared libraries: libstrings.so: cannot open shared object file
```

At HEAD the same program is refused at compile time by the guard added in
`e53eff428`, naming `memcmp`, `libstrings.so`, and the header it was derived
from. That is strictly better and it is not the fix.

# Why it is blocked rather than fixed here

The right answer is not "refuse a header import" and not "add `strings` to the
curated list" — a header import is a real NilPy feature and the curated list's
exclusion is deliberate and correct. The right answer is that a soname the
COMPILER derived from a file name should be **verified against the library's
own dynsym** before it becomes a `DT_NEEDED`, and dropped when nothing answers.
That is
[[feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym]],
which is the front of the SDL chain and already owned.

This row exists so that ticket has a second consumer recorded against it: the
SDL case is a header whose derived library exists and answers, and this is a
header whose derived library does not exist at all. A fix that handles only the
first leaves this one refusing a program CPython runs.

# How it was found

frankZ, from `test_nilpy_qualified_name_error_names_the_receiver` going red and
taking the `test-nilpy` tier down with it (every row after Makefile:1313 was
unrun). That fixture's own comment claimed `strings` was "a Pascal RTL unit
wearing a Python module's name" — it never was, and the fixture has moved to
`zlib`, which genuinely is.
