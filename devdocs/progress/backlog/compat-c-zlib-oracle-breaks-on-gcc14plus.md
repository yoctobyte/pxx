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

## Fix

Add the minimal escape to the oracle's `gcc` line in the `test-zlib` recipe:

```make
gcc -w -Wno-error=implicit-function-declaration -Ilibrary_candidates/zlib ...
```

Measured alternatives that also build: `-fpermissive`, `-std=gnu89`. Prefer
`-Wno-error=implicit-function-declaration` — it restores the pre-gcc-14
default without changing the language dialect the oracle is compiled under,
which matters because that binary IS the reference the comparison trusts.

Any other corpus target that builds a pinned third-party C tree with a modern
gcc is exposed to the same promotion — worth a sweep of the oracle build lines
(`tcc`, `sqlite`, `lua`, `quickjs`, `duktape`) rather than fixing only zlib.

## Note for the watcher fleet

This is the second category the cutover comparison was meant to catch: a test
that was **never host-portable**, silently green only because every watcher so
far ran an older toolchain. It is not an xeon environment gap and installing
packages will not fix it.
