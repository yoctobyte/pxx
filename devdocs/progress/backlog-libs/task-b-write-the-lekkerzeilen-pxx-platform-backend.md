---
slug: task-b-write-the-lekkerzeilen-pxx-platform-backend
track: B
type: task
prio: 85
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [lekkerzeilen, nilpy, sdl2, opengl, demo]
blocked-by:
  - feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym
  - bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register
  - bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved
  - bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment
  - bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed
summary: "lekkerzeilen/platform/_pxx.py IS A 39-LINE STUB whose every entry point raises NotImplementedError. The app has a two-backend portability seam -- ctypes for CPython (327 lines, works) and pxx (not written) -- so EVEN IF ALL 32 MODULES COMPILED THE DEMO WOULD NOT RUN. This is the real distance to a running demo and no module-count ratio shows it. The stub's own docstring specifies the work: translate _ctypes_backend with the ctypes machinery removed -- `import SDL2/SDL.h`, `import GL/gl.h`, constants from the headers' #defines, out-parameters return-lifted by the compiler, no CDLL/restype/argtypes/create_string_buffer. Writing it is allowed: the owner's standing rule on this target is that we MAY change lekkerzeilen's source."
---

# CHAIN STATE 2026-09-10, after 967f9cc93

`bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed` is CLOSED, and
it was the thing keeping SDL programs from executing. Re-measured over every
header in `/usr/include/SDL2` (78 files, not the 23 sampled before):

```
0   emit an invented lib<headername>.so   (was 20 of 23 sampled)
71  build AND RUN
7   refused at compile time
```

The 7 are two known walls and neither is a library-naming problem:

- `close_code.h` — an `#error`, by design; that header is only valid after
  `begin_code.h`. Not a defect.
- `SDL.h`, `SDL_cpuinfo.h` and the four `SDL_test*.h` — the AVX-512
  `MAX_PROC_PARAMS` wall, reached only through gcc's `<immintrin.h>` via
  `SDL_cpuinfo.h`/`HAVE_IMMINTRIN_H`, exactly as recorded below.

So the remaining blocker on `import SDL2/SDL.h` is the `immintrin.h` route, and
that is the same fork already written up: raise the limit (which needs
`bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type` first), or
ship a pxx-owned `immintrin.h` that declares nothing. Still not decided
unilaterally.

`import GL/gl.h` was already clean.

# MEASURED 2026-09-10: SDL.h is not blocked on MAX_PROC_PARAMS

`import "/usr/include/SDL2/SDL.h"` compiles **clean, rc=0**, with a stub
`immintrin.h` on `-I`. The parameter-limit wall
(`bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment`)
is reached only through gcc's AVX-512 intrinsic headers, which SDL pulls in via
`SDL_cpuinfo.h`/`HAVE_IMMINTRIN_H` and does not otherwise need. That ticket's
own fork asked *"measure which wall comes next before choosing"* — the answer
is that there is no wall behind it for this header, so the cheap option (a
pxx-owned `immintrin.h` that declares nothing and fails by NAME) unblocks SDL
without raising the limit at all. Not shipped yet: whether pxx should carry
such a header is a real choice and it is written up on the MAX_PROC_PARAMS
ticket, not decided here.

**The next real wall is library naming.** The binary links against `libsdl.so`
— derived from the header NAME — where the installed library is
`libSDL2-2.0.so.0` (`libSDL2-2.0.so` and a 32-bit twin also present). The
directory is `SDL2/`, so the directory-derivation path
(`feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym`,
landed) should be the one answering here and is not. That is the thing standing
between this ticket and a linking SDL program.

# Why this is the headline and the module census is not

`platform/__init__.py` selects a backend at import time (`_select_backend`,
:95-97) and exposes `gl`, `open_window`, `probe`, audio and controller openers
from whichever it picked. Under pxx it picks `_pxx`, and `_pxx`'s every name is
`_unimplemented`, which raises. The seam is honest by design — its docstring
says *"Kept as a stub so the seam in `__init__.py` stays honest: if anything
above this package ever reaches for ctypes, this file is what will notice."*

So the distance to a running demo is: compile the 32 modules **and write a
327-line binding**. A census that reports 8 of 32 is true and does not say this.

# What the work is, per the stub's own spec

> *"this backend should be a translation of `_ctypes_backend` in which the
> `ctypes` machinery simply disappears: no CDLL loading, no restype/argtypes
> declarations, no create_string_buffer. The constants come from the headers'
> `#define`s, and out-parameters are return-lifted by the compiler."*

It is therefore a PROOF of the nilpy C-header-import story on a real program,
not a shim — the same mechanism as the wrapper-free `import sqlite3`.

# The blocker that is actually load-bearing

`import SDL2/SDL.h` needs
[[bug-c-inline-asm-constraint-q-is-unsupported-and-it-blocks-every-sdl-header]].
That ticket has sat in `backlog-cfront` while the two sibling header bugs
(lowercased library name, header in a subdirectory) were fixed and closed. It is
now on the critical path of the priority target.

# A source-side item, and it is the owner's own constraint being broken

`gfx.py` reaches for ctypes ABOVE the seam — `ctypes.c_int`, `ctypes.byref`,
`ctypes.create_string_buffer`, `(ctypes.c_char_p * 1)(encoded)` — which
`docs/design.md` constraint C2 forbids and which `_pxx.py`'s docstring predicted
would be noticed here. `capture.py` does the same. Those out-parameter and
string-buffer idioms have to move below the seam (or be expressed as return-
lifted calls) for `gfx` to compile under pxx at all. **Do NOT add a
`mimic_ctypes`** — the settled direction on this target is to bind natively, and
a ctypes shim would make the seam's whole purpose moot.

## 2026-09-10 — the Q/q blocker cleared and SDL2 still does not import

`366e0e8a9` landed `Q`/`q` (a register CLASS a/b/c/d, so it needed a third
allocation phase between the fixed pins and the general pool — the ticket's own
*"the difference is allocation"* was the accurate sentence) plus the `%b`/`%w`
operand modifiers, whose absence was the next wall on the same line. frankH
recorded the expectation first and it was wrong in the useful direction: **it
expected `=Q` to unblock SDL2 and it did not.**

**Two walls now in front of `import "/usr/include/SDL2/SDL.h"`, in order:**

1. **The derived soname** — the import stops at `memcmp` coming from `libsdl.so`
   **before** reaching any asm. That is
   [[feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym]],
   which was filed at prio 50 the same morning and is now the FRONT of this
   chain. frankH's measurement confirms that ticket's own design rather than
   contradicting it: `libSDL2-2.0.so.0` exports `SDL_Init` and
   `SDL_CreateWindow`, while `libnet.so.9` exports **zero** of `net/if.h`'s
   symbols (`if_nametoindex` is in libc). A dynsym check accepts the first and
   rejects the second, which is exactly the distinction the ticket says makes the
   directory-derived guess safe.
2. **`%h0`, the high byte** —
   [[bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register]]. The encoder
   cannot name `ah/ch/dh/bh` at all: at byte width it forces a REX prefix for
   register numbers 4..7 (in its vocabulary those are `spl/bpl/sil/dil`), and REX
   is what makes the high-byte forms unencodable. Emitting one anyway assembles
   quietly to `spl` — **a wrong register with no diagnostic**, which is why it is
   refused by name now and filed with a disassembly control rather than patched
   in passing from a C ticket.

Both are wired into this task and into the umbrella, so `effective_prio` carries
90 to them. The ordering matters: clearing `%h` alone does not make SDL2 import,
because the soname wall is in front of it.

---

## 2026-09-11, frankB — MEASURED: the "cheap half" of the ctypes work is COSMETIC, and I am not doing it

This ticket's summary already says the important thing — even if all modules
compiled the demo would not run. What follows is the number for the other half of
the ctypes story, because the split is being read as "one cheap job and one big
job" and the cheap one does not buy what its cost suggests.

A per-module census at compiler d28aae4157c8 — each of the 28 runtime modules
compiled ALONE as `import <mod>` — returns 22 compiling and 6 blocked. One of
those six is an instrument error and not a wall: `traffic.py` reports
`nearest() takes exactly 2 argument(s), got 3` at :277 because compiling it alone
leaves world.py's 4-argument `nearest` out of the compilation, so the
candidate-class scan picks one of traffic.py's own two same-named methods
(:161 and :1035). `import world` + `import traffic` in ONE compilation is rc=0,
confirmed by two seats. So the census's own unit of compilation manufactures that
row, and the honest reading is 22 clear, FIVE real blockers, one mis-scored.

Two of the five are `import ctypes`: `capture.py` and `gfx.py`. The umbrella's reading is that those two import ctypes
at module level with no seam, so the fix is a corpus edit routing them through
the existing try/except. That is true of `capture.py`. It is NOT true of
`gfx.py`:

| module | `ctypes.` uses | what it uses |
| --- | --- | --- |
| `capture.py` | **1** | `create_string_buffer` |
| `gfx.py` | **60** | everything below |

Nine distinct names between them: `byref`, `sizeof`, `create_string_buffer`,
`c_int`, `c_uint`, `c_float`, `c_char`, `c_char_p`, `c_void_p` — plus the
`(TYPE * N)(...)` array-type construction, which is a tenth thing and not a name.

**gfx.py IS the OpenGL marshalling layer.** `ctypes.c_uint(0)` then
`gl.GenBuffers(1, ctypes.byref(vao))`, `(ctypes.c_float * 16)(*mat.m)`,
`ctypes.sizeof(data)` into `gl.BufferData`, `ctypes.c_void_p(offset)` as an
attribute pointer. Routing its import through a seam makes the module COMPILE and
leaves it unable to do the one thing it exists for. The census count would move
by two and the demo would move by zero — which is this repo's own warning about
first-failure censuses arriving from the other direction: not a wall hiding
walls behind it, but a wall whose removal delivers nothing.

The owner's standing line for this target (2026-09-10) points the same way:
shims are the path, programs should stop contorting for the frontend, and a
plain-Python shim counts as native code. A corpus edit that hides an import the
module then cannot use is the program contorting for the frontend.

So: **the two ctypes rows are one missing capability, not two module fixes.**
Whoever takes them should take `mimic_ctypes` — nine names and an array-type
constructor, which is a bounded surface, not the whole of CPython's ctypes — and
NOT the seam edit. If the seam edit is done anyway for some other reason, say in
the resolution that ctypes is not solved, or the next reader will read two
cleared rows as the capability landing.

`bindings.py`'s `undefined variable (_pxx)` is the fifth blocker and is the
39-line stub this ticket is about, reached from the other side.

Not claiming this ticket; recording the measurement so it is not re-derived.
