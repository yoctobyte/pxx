---
slug: bug-b-gl-triangle-demo-imports-gl-from-libgl-c-so-which-does-not-exist
title: examples/gl/triangle cannot build -- a C header unit's library is its file name, and gl_c names no library
track: B
type: bug
prio: 50
status: backlog
found: 2026-09-19
found-by: frankH (demo sweep, Track B demos group)
summary: >
  The only one of 36 demos that does not build, under both the pin (bc884808fda5)
  and HEAD (7ca269bd75ad). `uses gl_c` imports lib/pcl/gl_c.h, and a C header
  unit's library is derived from its stem (CHeaderStem), so every GL entry point
  is imported from libgl_c.so, which does not exist. Since e53eff428 (2026-09-10)
  the compiler refuses that at build time; before that it built and would have
  died at exec, so the demo has probably never run. glCreateShader is exported
  by libGL.so.1 and libOpenGL.so.0 here, NOT by libepoxy (which exports
  epoxy_glCreateShader), although gl_c.h's comment says libepoxy. Two ways to
  fix it, both unbuilt; see Options.
---

## Measured

- `make demos`-equivalent build (same flags) with the pin and with HEAD:
  `this build would die at exec: glCreateShader is imported from libgl_c.so,
  which no library on this machine answers to ... Name the library explicitly
  instead, with an external '<soname>' clause`.
- `nm -D --defined-only`: glCreateShader is defined in
  /usr/lib/x86_64-linux-gnu/libGL.so.1 and libOpenGL.so.0 (glvnd), and 0 times in
  libepoxy.so.0.
- No C-side way exists to name a header unit's library: CPPragma knows pack and
  push/pop_macro only, and CHeaderStem is a table (gtk3_c is aliased there for
  the same reason).
- Not measured: whether Xvfb on this box offers a GL 3.3 core context (glxinfo
  is not installed), so a fixed build's window may still need a real display to
  verify.

## Options

1. **Alias in the compiler**, as gtk3_c already is: `gl_c` -> stem `GL` in
   CHeaderStem (compiler/pasparser_proc.inc), plus the default-system entry in
   CHeaderDefaultSystem, plus a check that CSonameForStem reaches libGL.so.1.
   It follows precedent, but it grows a special-case table, needs A/N review
   (the resolver is Track N's 2026-09-10 design), and stays inert for this
   Track-B demo until a pin carries it.
2. **Make gl_c a Pascal unit** whose routines say `external 'libGL.so.1'`, as
   the compiler's own diagnostic prescribes. It is Track B only and works under
   the current pin. Cost: the curated header becomes Pascal declarations, and
   gtk3gl.pas (the other `uses gl_c`) must still compile.

Recommendation: 2, because it is the remedy the refusal names and needs no pin.
If a third C-header unit hits this, the right answer is a mechanism for a header
to declare its own library, not a third table entry.
