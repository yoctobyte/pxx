---
slug: bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed
track: C
prio: 75
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [cfront, headers, elf, sdl2, lekkerzeilen, dt-needed]
blocked-by: []
summary: "Importing almost any SDL2 header emits TWO DT_NEEDED entries: the correct `libSDL2-2.0.so.0` AND an invented `libsdl_<headername>.so` that does not exist on any box. The bogus one alone makes every SDL program die at exec with `cannot open shared object file`, so `import SDL2/SDL.h` compiles rc=0 and cannot run. 20 of 23 SDL2 headers measured are affected. CONTROL: FLAC/stream_decoder.h with a function actually called emits ONLY `libFLAC.so.14` and runs, so the header-directory derivation works end to end — this is the unresolvable FALLBACK not being dropped once the real library is found. This is the last thing between task-b and a running SDL program."
---

# Measured

```
import "/usr/include/SDL2/SDL_version.h"   ->  libsdl_version.so  libSDL2-2.0.so.0   [loader fails]
import "/usr/include/SDL2/SDL_clipboard.h" ->  libsdl_clipboard.so libSDL2-2.0.so.0  [loader fails]
import "/usr/include/FLAC/stream_decoder.h" -> libFLAC.so.14                          [RUNS, returns True]
import "/usr/include/net/if.h"             ->  (none)                                 [runs]
import "/usr/include/GL/gl.h"              ->  (none)                                 [runs]
```

20 of 23 SDL2 headers emit the bogus pair; 3 are clean.

The binary has **no undefined symbols at all** in the `print("x")` case, so
neither entry is referenced — yet both are recorded, and the unsatisfiable one
is fatal at exec.

`libsdl_version.so` is the name invented from the header's FILE name.
`CSynthMissingLibs` is by construction the list of sonames this host cannot
resolve, so an entry that is still on that list at ELF-write time is known-bad
before it is written.

# Why FLAC works and SDL2 does not — narrowed, not solved

`CSynthDirAnswersFor` upgrades a proc's library only when the directory's
library actually EXPORTS that proc's symbol (the `net/if.h` guard, deliberate).
Procs it answers for get `libSDL2-2.0.so.0`; any proc it does NOT answer for
keeps the invented soname, and that is what reaches DT_NEEDED. FLAC resolves
through pass 1 (strict `libFLAC.so.`), SDL2 through pass 2 (the loosened `-`
arm that reaches `libSDL2-2.0.so.0`) — so pass 2 is the first place to look,
but I did not establish that the pass is the discriminator.

# Two hypotheses tested and DEAD — do not re-run these

1. **Function-like macros mistaken for declarations.** No. `SDL_clipboard.h`
   and `SDL_power.h` have ZERO function-like macros and are both affected;
   `SDL_version.h` has three and is affected the same way. No correlation.
2. **`SDL_FORCE_INLINE` not recognised as `static inline`.** No. It expands to
   `__attribute__((always_inline)) static __inline__`, and a minimal header
   declaring both that form and plain `static __inline__` compiles, inlines and
   runs correctly with no UND symbol and no DT_NEEDED. The attribute prefix is
   handled.

A grep of the preprocessed `SDL_clipboard.h` finds four names declared but not
exported by libSDL2 — `SDL_memcpy4`, `SDL_memset4`, `SDL_size_add_overflow`,
`SDL_size_mul_overflow` — which is a live lead but NOT confirmed as the cause:
those names are also `#define`d to `_SDL_*_builtin` variants under a
`__builtin_*` conditional, so the grep may be reading a shape that never
reaches the parser. **Check that before building on it.**

# The fix is probably independent of the cause

Whatever keeps one proc on the invented soname, a name known to be unresolvable
should not reach DT_NEEDED. The caution is that dropping it silently could turn
a loud `cannot open shared object file` into a quiet `undefined symbol` at
first call — so the honest shape is likely to ERROR at the site that still
holds an unresolvable library, naming the symbol that kept it, rather than to
drop the entry. That also surfaces the real cause instead of hiding it.

# Repro

```
printf 'import "/usr/include/SDL2/SDL_version.h"\nprint("v")\n' > /tmp/v.npy
./compiler/pascal26 /tmp/v.npy /tmp/v && readelf -d /tmp/v | grep NEEDED && /tmp/v
```
