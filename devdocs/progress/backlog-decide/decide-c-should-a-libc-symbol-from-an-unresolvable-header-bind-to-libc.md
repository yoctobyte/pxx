---
slug: decide-c-should-a-libc-symbol-from-an-unresolvable-header-bind-to-libc
track: U
type: decide
prio: 55
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [cfront, headers, elf, dt-needed]
blocked-by: []
summary: "An import whose derived soname no library answers to is REFUSED, even when the compiler can see exactly which library exports the symbol. WIDENED 2026-09-10 past the libc case it was filed for: the general question is whether to resolve such an import by asking who exports the symbol. MEASURED, and it makes the fork decidable — over 1439 native libraries, 6 of 8 sampled symbols resolve to exactly ONE library (crc32, compress, deflate, inflate -> libz alone; sqlite3_open -> libsqlite3; png_read_png -> libpng16), and where several answer they are VARIANTS OF ONE LIBRARY, never unrelated ones: SDL_Init -> libSDL-1.2/libSDL2-2.0/libSDL3, curl_easy_init -> libcurl/libcurl-gnutls. So the risk is not 'any library could claim any symbol'; it is choosing between versions of the right library, which the header's directory already disambiguates for SDL2. The honest shape is therefore search, and ERROR naming the candidates when more than one family answers."
---

# What happens now

```
printf 'import "/usr/include/strings.h"\nprint(ffs(8))\n' > /tmp/pc.npy
./compiler/pascal26 /tmp/pc.npy /tmp/pc
pascal26:1: error: this build would die at exec: `ffs` is imported from
libstrings.so, which no library on this machine answers to. ...
```

`ffs` is in libc.so.6. `strings.h` sits directly in `/usr/include`, so
`CSynthDirName` is `include`, `LdCacheDirCandidate` finds no `libinclude.so`,
state goes to 2, and `CSynthDirAnswersFor` exits before its libc/libm arms —
the arms that would have answered correctly.

Under `SDL2/SDL_version.h` the same symbols DO resolve, because that directory
names an installed library and the state-1 gate opens. So the outcome depends
on a property of the header's directory that has nothing to do with where the
symbol lives.

# The scope is deliberate, and its argument is in the code

`pasparser_proc.inc`, `CSynthDirAnswersFor`:

> SCOPED to a header whose directory DID name a real library (state 1).
> Without that, a header naming no library at all keeps today's error, which is
> the right answer for it — this is not a general licence to satisfy any
> unresolved symbol out of libc.

That is a real hazard and not a hypothetical: a header declaring its own `open`
or `index` wrapper would bind to libc's under the wider rule, silently, where
today it errors loudly.

# The fork, stated as what we want

**Do we want an import whose library we cannot name to fail loudly, or to
succeed whenever the symbol demonstrably comes from libc?**

The evidence standard is the same either way — libc's own `.dynsym` is read,
not guessed. What changes is which mistake we prefer to make: refusing a build
that would have worked, or linking a same-named-but-different function.

Note the wider rule is not "satisfy anything out of libc": a header
synthesising `libfoo.so` and declaring `foo_init` still errors, because libc
does not export it. Only names libc actually defines are absorbed.

# Not urgent — but the green here has NO OWNER

The one fixture that hit this (`test_nilpy_qualified_name_error_names_the_
receiver`) was moved off `strings` in `0997c6088` for an unrelated and correct
reason, so no row is red on it.

**Read that as luck, not as evidence.** Nothing in the tree asserts the current
behaviour. The row that would have caught a change to it left for reasons that
had nothing to do with this question, so if the fork is decided the other way,
or if someone moves a fixture back onto a top-level header, there is no
instrument standing here to notice. The silence is an absence of coverage
wearing the shape of a passing suite.

Deliberately NOT fixed by writing a test now: the behaviour is the thing under
question, and pinning it would pin one arm of the fork before it is decided —
the assertion would then have to be deleted by whoever answers, which makes it
an obstacle rather than a guard. Whoever settles this should land the test in
the same commit, in whichever direction they choose.

(frankB's observation, on reading the ticket. Recorded here rather than in a
message because a message is not where the next reader looks.) Found while landing
`bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed`, whose fix
does not touch this scope.

# WIDENED 2026-09-10 — the libc case is one instance, and the fork is bigger

frankuser measured a two-line repro that needs no SDL2 and no window:

```
import zlib
x = zlib.crc32
-> this build would die at exec: `crc32` is imported from libzlib.so,
   which no library on this machine answers to
```

`zlib.h` synthesises `libzlib.so`; the library is `libz.so.1`. And the sibling
shows why this survived: `sqlite3.h` synthesises `libsqlite3.so`, which EXISTS,
so `import sqlite3` binds and runs. **One wrong rule, and the first case anyone
tried was the one where it happens to be right.**

Three shapes, all measured at `39441c6fe`:

| header | derived | real library | outcome before |
| --- | --- | --- | --- |
| `sqlite3.h` | `libsqlite3.so` | `libsqlite3.so.0` | binds — stem IS the library |
| `zlib.h` | `libzlib.so` | `libz.so.1` | REFUSED — stem is not |
| `SDL2/SDL_version.h` | `libsdl_version.so` | `libSDL2-2.0.so.0` | binds via the DIRECTORY rule |

The libc/libm arms this ticket was filed about are the same question with the
answer already known. The real question is one notch out.

## The measurement that makes it decidable

Asking **which library on this box exports the symbol** is not a guess: it is
the same `.dynsym` evidence standard the directory rule already uses. Scanned
all 1439 native entries in `ld.so.cache`:

```
crc32            1 library   libz
compress         1 library   libz
deflate          1 library   libz
inflate          1 library   libz
sqlite3_open     1 library   libsqlite3
png_read_png     1 library   libpng16
curl_easy_init   2           libcurl, libcurl-gnutls
SDL_Init         3           libSDL-1.2, libSDL2-2.0, libSDL3
```

**Ambiguity is real but structured.** Six of eight are unique. The two that are
not are *variants of one library* — two TLS backends, three major versions —
never two unrelated libraries competing for a name. That is a far narrower
hazard than "satisfy any unresolved symbol from anywhere", which is what the
existing scope comment was written against, and it means a search that ERRORS
when more than one family answers loses almost nothing.

Cost is bounded and lands only on a path that today is a hard error: one pass
over the cache, and 35.7s here through 1439 `readelf` invocations — the
compiler reads ELF directly and would be far cheaper.

## The fork, restated

**Does an import name a LIBRARY, or a place to look for one?**

If it names a library, a derived soname that answers to nothing is an error and
the user should say which library they meant. If it names a place to look, the
compiler should find the library that actually exports what was asked for.

## Point fix landed meanwhile, and it is recorded AS a point fix

`zlib.h` -> `libz.so.1` is now a row in `CSonameForStem` (`import zlib` builds,
links `libz.so.1` and runs; `test_nilpy_import_zlib.npy` asserts the value, the
ABSENCE of `libzlib.so` and the PRESENCE of `libz.so.1`). That unblocks
`feature-n-mimic-zlib-...`, and it is the THIRD row of a table whose premise is
that the header stem is the library name. It does not close this ticket and
should not be read as evidence the class is handled.
