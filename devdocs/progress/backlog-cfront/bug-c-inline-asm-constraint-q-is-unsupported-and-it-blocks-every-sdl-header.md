---
slug: bug-c-inline-asm-constraint-q-is-unsupported-and-it-blocks-every-sdl-header
track: C
prio: 55
type: bug
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [cfront, inline-asm, sdl2, headers, lekkerzeilen]
blocked-by: []
summary: "`__asm__(\"xchgb %b0,%h0\": \"=Q\"(x):\"0\"(x))` at /usr/include/SDL2/SDL_endian.h:166 is refused with `inline asm constraint \"=Q\" is not supported -- this frontend reads \"r\", \"rm\", \"m\", \"g\" and the fixed-register letters a b c d S D`. Measured 2026-09-08 against compiler/pascal26 a7b03135f504. ONE LINE IN ONE HEADER BLOCKS EVERY SDL2 IMPORT, and therefore the whole native-binding route for the lekkerzeilen showcase: `import \"/usr/include/SDL2/SDL.h\"` gets no further. GL/gl.h by contrast imports, compiles and RUNS today."
---

# Repro

```
$ printf 'import "/usr/include/SDL2/SDL.h"\nprint("reached")\n' > h.py
$ ./compiler/pascal26 h.py out
pascal26:167: error: C: inline asm constraint "=Q" is not supported
```

`SDL_endian.h:166`: `__asm__("xchgb %b0,%h0": "=Q"(x):"0"(x));` — SDL's
16-bit byteswap.

# What `Q` means, and why the machinery is probably already there

In GCC's x86 constraint set, `Q` is *any register addressable as `rl`/`rh`* —
i.e. one of `a`, `b`, `c`, `d`. The diagnostic's own list says this frontend
already reads **the fixed-register letters a b c d**. So `Q` is the
"any one of the four" form of letters that already exist, rather than a new
register class.

**That is an argument for where to look, not a claim that the fix is one line.**
The difference between a fixed letter and a choose-one-of-four letter is
allocation, and this ticket has not read that code.

# Scope beyond SDL

`Q` is common in hand-written x86 headers wherever a byte-half register is
needed. Whoever fixes it should check the sibling letters in the same family
(`R`, `q`, `l`) rather than adding one row — the neighbours are the same
mechanism and the second path is the one that stays broken.

Same family as the resolved
`bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386`.
