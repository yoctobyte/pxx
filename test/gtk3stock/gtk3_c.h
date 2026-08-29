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
