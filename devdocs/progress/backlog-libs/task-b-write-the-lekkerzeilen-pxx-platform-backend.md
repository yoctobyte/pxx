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
