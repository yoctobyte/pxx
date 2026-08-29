/* SPDX-License-Identifier: Zlib */
/* The STOCK GTK3 surface, reached by including the installed headers rather
   than re-declaring them. Shadows lib/pcl/gtk3_c.h for this one test via
   -Futest/gtk3stock, so the curated binding and its consumers are untouched
   while the stock-header path is gated.

   It lives in its own directory on purpose. Several tests already pass -Futest,
   and a `test/gtk3_c.h` would silently shadow the curated binding for every one
   of them -- the failure landing in a test that never mentioned GTK.

   The unit name must stay `gtk3_c`: CHeaderStem maps that stem to `gtk-3`, which
   is what makes the link land on libgtk-3.so.0 (asserted by the caller). */
#include <gtk/gtk.h>

/* Same assertion as lib/pcl/gtk3_c.h, and this copy is the one that had to be
   here: the caller's `readelf -d | grep libgtk-3.so.0` was documented as
   asserting the VERSION, and it cannot. The stem above forces libgtk-3.so.0
   whatever -I is in effect, so dropping the flag and building this very test
   against GTK2 headers still satisfies that grep -- measured. A check that
   passes on the state it exists to reject is not a weak check, it is a
   decorative one, and it read as coverage for the stock-header path.
   feature-b-pcl-should-assert-its-gtk-version-rather-than-rely-on-an-accident */
#if !defined(GTK_MAJOR_VERSION)
#error "test/gtk3stock: <gtk/gtk.h> did not define GTK_MAJOR_VERSION -- no GTK headers found. Pass the GTK3 include root."
#elif GTK_MAJOR_VERSION < 3
#error "test/gtk3stock: <gtk/gtk.h> resolved to GTK2, but this test exists to gate the stock GTK3 path. Pass -I for the gtk-3.0 include root."
#endif
