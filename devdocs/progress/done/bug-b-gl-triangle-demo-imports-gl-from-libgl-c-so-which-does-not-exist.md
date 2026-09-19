---
slug: bug-b-gl-triangle-demo-imports-gl-from-libgl-c-so-which-does-not-exist
title: examples/gl/triangle cannot build -- a C header unit's library is its file name, and gl_c names no library
track: B
type: bug
prio: 50
status: done
found: 2026-09-19
found-by: frankH (demo sweep, Track B demos group)
summary: >
  FIXED 2026-09-19 by option 2, and it took three fixes, not one. (1) gl_c is now
  a Pascal unit, lib/pcl/gl_c.pas, whose entry points say external 'libGL.so.1'
  (the C header named no library, so its imports went to libgl_c.so, which does
  not exist). (2) GL_STATIC_DRAW was $88B4 in the old header and is $88E4 in GL,
  so glBufferData refused it (GL_INVALID_ENUM) and nothing was drawn. (3)
  glarea's CallRenderMethod called OnRender without Sender, so the handler's W/H
  were shifted, giving a 480x480 viewport. Also the label's Chr(176) is now UTF-8.
  Verified under Xvfb (Mesa 4.5 core) by screen readback, with pin v411 and HEAD.
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

## Resolution (2026-09-19, frankH)

Option 2, landed live, needing no pin. Verified under Xvfb with Mesa's software
GL (`glGetString(GL_VERSION)` = 4.5 Core Profile), by reading the root window
back through Python's Gdk bindings and counting pixels, built with pin v411
(bc884808fda5) and with HEAD. Each fix was measured separately:

1. **The library.** `lib/pcl/gl_c.pas` replaces `gl_c.h` and keeps the unit
   name. `readelf -d` now shows DT_NEEDED on libGL.so.1. Result: it builds, the
   GL clear colour fills the area, and there are 0 triangle pixels.
2. **The constant.** `glGetError` checked after every setup call named
   glBufferData as the source of 1280 (GL_INVALID_ENUM). Of the 14 hex
   constants compared against `/usr/include/epoxy/gl_generated.h`, only
   GL_STATIC_DRAW differed ($88B4 in the header, $88E4 in GL). This was a typo
   carried from the old header, not an ABI fault: a C probe library shows pxx
   passing all four glBufferData-shaped arguments correctly, both in isolation
   and from a method with the external declared in a unit. Result: triangle
   pixels drawn.
3. **The call shape.** The handler saw W=480, H=480 for a 640x480 area.
   CallRenderMethod passed (Self, w, h), while the PCL event shape is (Self,
   Sender, ...), as CallPaintMethod passes it. It now passes the TGLArea as
   Sender. Result: W=640, H=480.
4. **The label.** `Chr(176)` is a raw 0xB0 byte, and GTK logged 223
   "Invalid UTF-8" warnings in 4s. It is now `#$C2#$B0`. Result: 0 lines of
   output.

Final: a 780x560 window, process alive, about 33k triangle-coloured pixels,
no stderr, under both compilers. solitaire_gui and life map the same windows
as before. gtk3gl.pas `uses gl_c` but calls nothing from it (its GL-area calls are gtk3_c's), so it compiles unchanged.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
