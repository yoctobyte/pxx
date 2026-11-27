---
slug: umbrella-pxx-compiles-the-gnome-c-base
title: "pxx compiles GNOME's C base: GLib, and as far up the GTK stack as C goes"
track: C
prio: 45
type: umbrella
status: open
created: 2026-11-27
found-by: owner (yoctobyte), via pixx-cc
owner: ""
blocked-by: []
summary: "Toss GNOME's C libraries at pxx: GLib/GObject/GIO first, then the rest of what GTK stands on that is C (libffi, pcre2, pixman, cairo, freetype, fontconfig, fribidi, libepoxy, graphene, gdk-pixbuf, libxkbcommon, wayland). The wall is C++: harfbuzz (needed by pango, so by GTK), Mesa's LLVM, GNOME Shell's JS engine. pxx does no C++ for now (owner, 2026-11-27), so full GNOME by pxx is not a goal; GNOME itself gets built with gcc to stress Rainyday."
---

# pxx compiles GNOME's C base

Owner, 2026-11-27: GNOME challenges the kernel and pxx; "pxx improves
fastest by just tossing code at it". On C++: *"we already sort-of said we
wouldn't do that, at least not for now ... that makes gnome by pxx not an
option for now. However, with gcc or possibly another compiler, that's not
any issue at all, and just stresses rainyday kernel and drivers."*

So this umbrella takes the C part only, as far as it goes.

## In order

1. **GLib** (GLib, GObject, GIO; with libffi, whose x86-64 .S is a good
   test of pxx's assembler, and pcre2). Done when GLib's `meson test`
   matches gcc's.
2. **The drawing and text stack in C:** pixman and freetype (Path B
   has them already), cairo, fontconfig, fribidi, libepoxy, graphene,
   gdk-pixbuf (with libpng and libjpeg-turbo).
3. **Input and Wayland:** libxkbcommon, wayland, wayland-protocols (shared
   with Panorama: coordinate with panorama-ae through pixx-cc).
4. **Stop at the C++ wall:** harfbuzz is C++, and pango (so GTK 3 and 4)
   needs it. Record the wall and stop: no C rewrites around it.

Each library: pinned source, a meson/autotools replay (the child ticket
of umbrella-pxx-compiles-systemd), and its own test suite equal to gcc's.

No workarounds: upstream source as written; a construct pxx refuses is a
pxx ticket.
