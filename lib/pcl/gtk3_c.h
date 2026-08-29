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
