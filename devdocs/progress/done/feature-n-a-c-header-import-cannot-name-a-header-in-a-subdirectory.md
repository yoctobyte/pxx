---
slug: feature-n-a-c-header-import-cannot-name-a-header-in-a-subdirectory
track: N
prio: 45
type: feature
status: done
owner: frankB
created: 2026-09-08
found-by: frankuser
tags: [nilpy, ffi, headers, imports, lekkerzeilen]
blocked-by: []
summary: "FIXED. A RELATIVE quoted `.h` path that misses beside the source now falls back to the C include roots and then /usr/include, so `import \"GL/gl.h\"` and `import \"SDL2/SDL.h\"` resolve without an absolute path baking a distribution layout into the source. Source directory FIRST, unchanged and asserted: the fallback only runs once the authoritative path has genuinely missed, so nothing that resolves today can move. `.h` ONLY and absolute paths untouched -- extending it to `.pas` would put Pascal unit resolution on a C search path, which is exactly `bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import`. The four BARE spellings the ticket measured (`import SDL2/SDL.h`, `import SDL`, `from SDL2 import SDL`, `import SDL2_SDL`) still answer `no unit named ...` and that is deliberate: they are the arm where a Python stdlib name must beat a C header, guarded by test_nilpy_import_c_header_still_works.npy. Composed with the soname fix next door, `import \"GL/gl.h\"` now links libGL.so.1 and runs."
---

# Measured

| spelling | result |
| --- | --- |
| `import sqlite3` | OK — flat header in /usr/include |
| `import SDL2/SDL.h` | `no unit named sdl2` |
| `import SDL` | `no unit named sdl` |
| `from SDL2 import SDL` | `no unit named sdl2` |
| `import SDL2_SDL` | `no unit named sdl2_sdl` |
| `import "/usr/include/SDL2/SDL.h"` | **works** (then hits the `=Q` asm gap) |
| `import "SDL2/SDL.h"` | resolves RELATIVE to the source dir, not the include path |

The quoted form already parses and already has a resolution path; what it lacks
is the include-path search that the bare form has. `import "SDL2/SDL.h"` looking
in `/usr/include` after the source directory would be the whole feature, and it
is the spelling a C programmer would already write.

# Why it matters for more than tidiness

`lekkerzeilen/platform/_pxx.py` — a stub its own author wrote for this — plans
`import SDL2/SDL.h`. An absolute path works but bakes `/usr/include` into the
source, so the file stops being portable and stops being a fair demonstration.
The showcase value is a Python program that compiles; a Python program that
compiles *on this distribution* is a weaker claim.

Note the name-collision rule already settled next door: a Python stdlib name
that also names a C header (`string`, `math`) must reach the Python module
first — see `test_nilpy_import_c_header_still_works.npy`, which guards the
ORDER. Any change here must keep that ordering.


# RESOLVED 2026-09-10

## What changed, and how little

One arm, in the `isPath` branch of the unit resolver, whose own comment read
*"The path is authoritative — no directory search chain, miss is an error."*
That is still true of an ABSOLUTE path. For a relative one it now falls through
to `CIncludeDirs` and then `/usr/include` — which is what the ticket asked for in
its own words: *"`import "SDL2/SDL.h"` looking in `/usr/include` after the source
directory would be the whole feature."*

## The ordering is the test, not the feature

A header beside the source must keep beating an include root — it is an explicit
local choice, and it is the same precedence `AddDefaultCIncludeDirs`' other
callers use. `test/ffi_local/beside_the_source_wins.npy` asserts it with two
files that have the **same relative spelling** (`sub/marker.h`) and different
constants, compiled with `-Itest/ffi_headers/` so both are reachable.

That row exists because the failure is silent: if the fallback ever ran first,
both headers resolve, both compile, and the program prints a different plausible
number. Nothing else in the suite would notice.

## Three things deliberately left alone

1. **Absolute paths.** They already name exactly one file; searching after one
   would answer a question the user did not ask.
2. **`.pas`.** Putting Pascal unit resolution on a C search path is
   `bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import`,
   whose silent half was a `uses strings` that bound, printed `ok:`, and carried
   a DT_NEEDED on `libstrings.so`.
3. **The bare forms.** `import SDL`, `import SDL2_SDL` and friends still answer
   `no unit named ...`, re-measured in a clean directory after the change. They
   go down the NON-path arm, where a Python stdlib name that also names a C
   header must reach the Python module first — the ordering
   `test_nilpy_import_c_header_still_works.npy` guards. Nothing here touches it.

   (Worth recording: the first re-measurement of `import SDL` looked like it had
   started resolving. It had — to `sdl.py`, a scratch file the previous probe had
   left in the same directory. The result was correct behaviour and the
   measurement was contaminated by its own earlier step. Re-run in a clean dir.)

## What the SDL2 case now does, which is not "works"

`import "SDL2/SDL.h"` resolves the header, and then the guard from the sibling
ticket refuses it: stem `SDL`, soname `libsdl.so`, which this host does not have
(the real one is `libSDL2-2.0.so.0`). That is a compile error where it used to be
`no unit named sdl2`, and it would have been a green build dead at exec had the
subdirectory search landed alone.

**So the two tickets had to land together**, and not for the reason either of
them gave: making headers in subdirectories reachable is precisely what makes
badly-derived sonames reachable, because a subdirectory is exactly where a
header's name stops resembling its library's. The follow-up that would finish
SDL2 is
`feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym`.

`lekkerzeilen/platform/_pxx.py` can now write the relative spelling it planned.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e53eff428.
