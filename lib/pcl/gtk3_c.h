/* SPDX-License-Identifier: Zlib */
/* The GTK3 surface PCL builds on, reached by including the INSTALLED headers
   rather than re-declaring them.

   This file used to be 135 hand-written prototypes with deliberately
   simplified types -- `void*` for every object pointer, `char*` for every
   string -- plus an invented `typedef void* PGtkWidget`. Each one was an
   independent guess that happened to be call-compatible, and
   test/test_c_gtk_window.pas still carries the scar in a comment: PGtkWidget
   was never declared, so it was silently a 4-byte int and TRUNCATED the
   pointer. Including the real headers makes the compiler check what was
   previously trusted. All 135 curated names were verified present in the stock
   headers before the swap (gcc address-taking probe, zero undeclared).

   The file is KEPT rather than deleted: the unit name `gtk3_c` is what
   CHeaderStem maps to the `gtk-3` stem, and that mapping is what makes the
   link land on libgtk-3.so.0.

   Consumers must pass -I for the GTK3 include root (the Makefile and
   tools/gui_suite.sh use $(GTK3_INC) / $GTK3_INC, one definition each). It is
   needed because gtk-2.0 is a default system include root and gtk-3.0 is not,
   and BOTH answer to `#include <gtk/gtk.h>` -- so the root that comes first
   decides the GTK version for every C consumer in the tree at once. Which one
   that should be is decide-which-gtk-a-bare-gtk-gtk-h-means, still open; this
   binding deliberately does not depend on the answer, and the -I goes away on
   its own if gtk-3.0 ever becomes the default root. */
#include <gtk/gtk.h>

/* ASSERT the version rather than inherit it from whoever set -I.

   Before this check, forgetting the include root still failed -- but only
   because PCL happens to call gdk_event_get_button, which is GTK3-only. That
   is a property of today's PCL surface, not a guard, and a guard that works by
   accident reads exactly like one that works by design. A consumer whose own
   surface is GTK2-compatible (gtk_init, gtk_main, gtk_window_new,
   gtk_container_add ... all exist in both) got no diagnostic at all.

   What it got instead is worse than the "wrong library" this was first filed
   as, because the LIBRARY is never wrong: the link stem comes from the unit
   name gtk3_c via CHeaderStem, so it is libgtk-3.so.0 either way. Only the
   HEADERS follow -I. So the silent outcome is GTK2 headers against the GTK3
   library -- an ABI mismatch, measured here with gcc as the oracle:

       sizeof(GtkWidget)   96 (gtk2 headers)  vs  32 (gtk3)
       sizeof(GtkWindow)  240               vs  56

   ...which no amount of link-time checking would catch, because the link is
   correct. Hence a check in the preprocessor, at the include, rather than at
   some consumer's call site.

   Both halves of this were measured against the pinned compiler before being
   relied on: pxx's C preprocessor honours #error (and correctly skips it in a
   false branch), and it really evaluates GTK_MAJOR_VERSION from the included
   header -- `#if GTK_MAJOR_VERSION == 2` fires without the flag and `== 3`
   fires with it, so the macro is being read, not defaulted.
   feature-b-pcl-should-assert-its-gtk-version-rather-than-rely-on-an-accident */
#if !defined(GTK_MAJOR_VERSION)
#error "lib/pcl: <gtk/gtk.h> did not define GTK_MAJOR_VERSION -- no GTK headers found. Pass the GTK3 include root (make: $(GTK3_INC); shell: $GTK3_INC, e.g. `pkg-config --cflags-only-I gtk+-3.0`)."
#elif GTK_MAJOR_VERSION < 3
#error "lib/pcl needs the GTK3 headers, but <gtk/gtk.h> resolved to GTK2. The link is libgtk-3.so.0 regardless (the stem comes from the unit name), so this would be a silent header/library ABI mismatch. Pass the GTK3 include root first: make $(GTK3_INC) / shell $GTK3_INC, e.g. `pkg-config --cflags-only-I gtk+-3.0`."
#endif
