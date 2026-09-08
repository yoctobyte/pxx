---
slug: decide-n-does-nilpy-emulate-ctypes-or-bind-natively
track: U
prio: 60
type: decide
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, ffi, ctypes, sdl2, opengl, lekkerzeilen]
blocked-by: []
summary: "lekkerzeilen binds SDL2 and OpenGL through ctypes and nothing else -- that is the whole platform layer (platform/_ctypes_backend.py, _sdl2.py, _gl.py, plus gfx.py). `ctypes` gets ZERO hits anywhere in pyparser.inc or pylexer.inc, so nilpy has no story here at all. This is the one blocker on that umbrella that is not small, and it is a design fork rather than a bug: emulate CPython's ctypes surface, or bind SDL2/GL through a pxx-native mechanism and change the source (which the owner has explicitly licensed for this project). Do NOT start building mimic_ctypes before this is settled -- picking the expensive arm by default is the failure mode this ticket exists to prevent."
---

# The fork

**A. Emulate `ctypes`.** `CDLL`, `c_int`/`c_float`/`c_void_p`, `POINTER`,
`Structure`, `byref`, `restype`/`argtypes`, callback thunks. Faithful, and any
Python that binds a C library then works unchanged.
*Cost:* a real FFI subsystem, and `ctypes` is a large and fiddly surface.

**B. Bind natively and change the source.** pxx already links C libraries — that
is what `lib/crtl` and every C-corpus target do. Give the platform layer a
pxx-native binding and rewrite `_sdl2.py`/`_gl.py` against it.
*Cost:* lekkerzeilen's platform layer diverges from CPython, so it no longer
runs unmodified under CPython unless the shim is written to satisfy both.

# What makes this decidable rather than a matter of taste

**The owner's cheat licence applies here and is the reason B is even on the
table** — see `umbrella-lekkerzeilen-compiles-and-runs-under-nilpy`. It is also
the arm the project's own README already leans toward: it refuses C extensions
and refuses asset files *specifically* to stay compilable under pxx, so the
author has already accepted shaping the source around this compiler.

**Against B:** `ctypes` is how ordinary Python talks to C, and a nilpy that
cannot is a nilpy that cannot run most real graphical Python. If the showcase
value is "your Python compiles", B weakens the claim.

**Recommendation: B for lekkerzeilen now, A as a separate future feature.**
Unblocking the showcase should not wait on the larger subsystem, and the two are
not exclusive. But this is a genuine intent fork and it is the owner's to settle.
