---
slug: bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed
track: C
prio: 75
type: bug
status: done
owner: frankH
created: 2026-09-10
found-by: frankH
tags: [cfront, headers, elf, sdl2, lekkerzeilen, dt-needed]
blocked-by: []
summary: "FIXED 967f9cc93. The guard was present, correct, and OVERWRITTEN -- which is why the machinery kept measuring as working. `CSynthDirAnswersFor` answered for every proc; `RegisterExternal` repaired `memcmp` to libc.so.6, and cparser.inc:13752 then wrote the invented soname back, because glibc gives memcmp an extern-inline body so the same name is declared twice. RegisterExternal runs DURING parsing and the C parser rewrites ProcLibrary on every re-declaration, so it was never the choke point its comment claimed. The check now runs as ResolveSynthImportLibraries from all three builders that read ProcLibrary[ExternalProc[i]] -- the --shared one included, which had the same exposure and nobody had looked at it. After: 0 of 78 SDL2 headers emit an invented soname (was 20 of 23 sampled), 71 build and RUN, and the 7 refusals are unrelated known walls -- close_code.h's deliberate #error and the AVX-512 MAX_PROC_PARAMS wall via immintrin.h."
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

# RESOLVED 2026-09-10 — and the section above it was WRONG about the cause

"Why FLAC works and SDL2 does not" guessed that `CSynthDirAnswersFor` did not
answer for some procs and those kept the invented soname. **It answered for all
of them.** The four unexported `SDL_*` names recorded as a live lead were not
the cause either, and nobody needs to check them now.

What actually happens, probed at every one of the ten `ProcLibrary[...] :=`
writers. For `memcmp`, proc index 2287, in this order:

```
cparser.inc:13707  (prototype arm)     -> libsdl_version.so
symtab.inc         (the resolution)    -> libc.so.6      <- correct
cparser.inc:13752  (header-body arm)   -> libsdl_version.so   <- overwrites it
```

Six libc functions arrive transitively through `SDL_stdinc.h` ->
`<string.h>`/`<ctype.h>`; glibc gives them extern-inline bodies, so each is
declared twice and the second declaration takes the header-body arm. The
resolution had already run, because a bodied header function CALLS them while
the header is still being parsed.

**`RegisterExternal` is not a choke point.** It runs during parsing, and the C
parser writes `ProcLibrary[procIdx]` again on every re-declaration it sees.

## The step that settled it

Both sides were printed with the PROC INDEX attached, and the indices MATCHED
(2287 in the fix-up and 2287 at emit). That ruled out "a second proc of the same
name" and left one reading. Two hypotheses had already died on this ticket; a
third guess was the obvious next move and would have been wrong again.

Also worth recording: the first probe printed nothing, because `elfwriter.inc`
has TWO DT_NEEDED builders and the live one for an executable is at ~150 inside
`PrepareDynamicData`, not the one at ~4807, which is `writeELFSharedX64`'s.

## The fix

`ResolveSynthImportLibrary` / `ResolveSynthImportLibraries` in `symtab.inc`,
called from `PrepareDynamicData`, `PrepareDynamicData32` and
`writeELFSharedX64` — the only three readers of `ProcLibrary[ExternalProc[i]]`
in the tree. The population is exactly the array the emitter iterates, so no
later write can miss it. `ErrorNoPos`, not `Error`: the parse is over by then.

This ticket's own prescription — error rather than drop the entry — is what the
code does, unchanged. Nothing is dropped silently.

Removing the call from `RegisterExternal` also closes the opposite direction: a
proc still unresolvable at registration but given `libc` by a LATER declaration
used to be refused for a state it no longer had.

## Regression test

`test/chdrsynth/m/synthclob.h` + `test_synth_soname_survives_redeclaration.pas`,
wired into `test-core`. Needs nothing installed but glibc. All three of its
conditions were ABLATED against the pre-fix compiler rather than argued — rename
the `m` directory and the build is refused instead; drop the bodied caller or
the re-declaration and the pre-fix compiler produces the correct binary. None of
the three variants would have caught this.

## Left open, deliberately

`decide-c-should-a-libc-symbol-from-an-unresolvable-header-bind-to-libc` — a
libc symbol reached through a header whose DIRECTORY names no library is still
refused (`ffs` from `strings.h`). That scope is another author's deliberate,
argued choice and nothing is red on it.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 349196870.
