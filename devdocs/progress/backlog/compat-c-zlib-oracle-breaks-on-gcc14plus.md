---
summary: "test-zlib's gcc oracle fails to build on gcc >= 14 (implicit-function-declaration is now an error), so the job reds on any modern host"
type: bug
track: C
prio: 45
---

# `test-zlib` gcc oracle no longer builds on gcc >= 14

- **Type:** test-harness portability (Track C — C tests / corpus targets)
- **Filed:** 2026-07-31 by Track T from the xeon watcher enrollment comparison.
- **Job:** `test-zlib#src:tools/install_lib_candidates.sh` — green on borg, red on xeon.

## The failure is in the ORACLE, not in pxx

```
library_candidates/zlib/gzlib.c:14:17: error: implicit declaration of
    function 'lseek'; did you mean 'fseek'? [-Wimplicit-function-declaration]
```

GCC 14 promoted `-Wimplicit-function-declaration` (and `-Wint-conversion`,
`-Wincompatible-pointer-types`) from warning to **error** by default. The
pinned zlib predates that and relies on implicit declarations in `gzlib.c` /
`gzread.c`. The recipe passes `-w`, which silences *warnings* and therefore no
longer helps.

So the job dies at `building gcc oracle ...` and never reaches pxx at all.

| host | gcc | oracle |
|---|---|---|
| borg | < 14 | builds → job green |
| xeon | 15.2.0 | fails → job red |

## pxx itself is fine — verified

Built the oracle with the error demoted, then ran the recipe's own comparison
at `f2f1a3a9add8`:

```
diff -u /tmp/orc.txt /tmp/got.txt   ->   no differences
```

The program pxx builds from the zlib sources produces **output byte-identical
to the gcc-built zlib's output**. (Behavioral parity against the oracle — not
a claim about matching gcc's machine code. See the claims-discipline table in
CLAUDE.md.) Nothing is wrong with the compiler here.

## Fix — `-DHAVE_UNISTD_H` on the oracle's gcc line

```make
gcc -w -DHAVE_UNISTD_H -Ilibrary_candidates/zlib ...
```

**Corrected 2026-07-31** (raised by `claude@borg`, re-measured on xeon before
adopting). An earlier revision of this ticket recommended
`-Wno-error=implicit-function-declaration`. That builds, but it is the wrong
fix: it *silences the diagnostic* while leaving `lseek`/`close`/`read`/`write`
genuinely undeclared, so they keep defaulting to `int` — on LP64 that truncates
`lseek`'s `off_t` return, which is a real latent miscompile in the binary we
then trust as the reference.

`-DHAVE_UNISTD_H` is zlib's **own** configuration macro: it makes `zutil.h`
include `<unistd.h>`, so the declarations are real and the errors disappear
because the cause is gone. This is what autoconf defines on every normal zlib
build, so the oracle ends up configured the way upstream intends rather than
patched around.

Measured on xeon (gcc 15.2.0, kernel 7.0):

| oracle gcc flags | result |
|---|---|
| *(none)* | fails — `implicit declaration of 'lseek'` |
| `-std=gnu17` | **fails** — gcc 14+ makes this an error regardless of `-std` |
| `-Wno-error=implicit-function-declaration` | builds, but leaves the decls missing |
| **`-DHAVE_UNISTD_H`** | **builds cleanly — adopted** |

Output parity re-confirmed with the `-DHAVE_UNISTD_H` oracle: the program pxx
builds from the zlib sources produces output byte-identical to the gcc-built
zlib's output.

Note for anyone reaching for `-std=`: it does not help. The promotion to error
in gcc 14 is independent of the language dialect.

Any other corpus target that builds a pinned third-party C tree with a modern
gcc is exposed to the same promotion — worth a sweep of the oracle build lines
(`tcc`, `sqlite`, `lua`, `quickjs`, `duktape`) rather than fixing only zlib.

## Note for the watcher fleet

This is the second category the cutover comparison was meant to catch: a test
that was **never host-portable**, silently green only because every watcher so
far ran an older toolchain. It is not an xeon environment gap and installing
packages will not fix it.
