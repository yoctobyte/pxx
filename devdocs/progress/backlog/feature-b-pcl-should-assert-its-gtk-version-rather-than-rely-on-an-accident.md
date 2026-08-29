---
track: B
prio: 30
type: feature
blocked-by: []
summary: "lib/pcl now includes the stock <gtk/gtk.h>, which resolves to GTK2 unless GTK3_INC puts the gtk-3.0 root first. Forgetting the flag fails loudly today only because PCL happens to call a GTK3-only function -- an accident, not a guard. The binding should assert its version."
---

# PCL should assert its GTK version rather than rely on an accident

Filed 2026-08-29 out of [[feature-b-migrate-pcl-off-the-curated-gtk3-header]],
at frank-coordinator's request, because the caveat is the kind that reads like a
guarantee if nobody writes it down.

## The situation

`lib/pcl/gtk3_c.h` is `#include <gtk/gtk.h>` now. On this box `gtk-2.0` is a
default system include root and `gtk-3.0` is not, and **both answer to that
spelling** — so the binding gets GTK3 only because `GTK3_INC` (Makefile,
`tools/gui_suite.sh`) puts the gtk-3.0 root first.

Forget the flag and the build fails loudly:

```
error: undefined variable (gdk_event_get_button)
  in: lib/pcl/gtk3widgets.pas
```

which looks like a guard. **It is not one.** It is loud only because PCL happens
to call `gdk_event_get_button`, which is GTK3-only. That is a property of today's
PCL surface, not a designed check. A consumer whose own surface is entirely
GTK2-compatible — and most of it is; `gtk_main`, `gtk_main_quit`,
`gtk_window_new`, `gtk_container_add` and the rest exist in both — would build
silently against the wrong library and only find out at runtime, or not at all.

A guard that works by accident reads exactly like one that works by design,
which is the whole reason this is a ticket and not a comment.

## Shape of a fix

A compile-time assertion inside the binding, so it fires at the include and not
at some consumer's call site. Something on the shape of

```c
#include <gtk/gtk.h>
#if !defined(GTK_MAJOR_VERSION) || GTK_MAJOR_VERSION < 3
#error "lib/pcl needs the GTK3 headers -- pass $(GTK3_INC) / $GTK3_INC"
#endif
```

**Check first that pxx's C preprocessor honours `#error` and evaluates
`GTK_MAJOR_VERSION` in an `#if`**; if it does not, that is the real prerequisite
and should be filed against the preprocessor rather than worked around here. A
fallback that needs no `#error` is a declaration that only parses under GTK3
(the moral equivalent of the accident, but deliberate and commented as the
assertion it is).

The runtime half already exists and should stay: `gtk_version_check` in
`tools/gui_suite.sh` asserts `libgtk-3.so.0` **is** and `libgtk-x11-2.0.so.0`
**is not** in DT_NEEDED. That covers the repo's own builds. This ticket is about
the consumer who is not the repo.

## Related

[[decide-which-gtk-a-bare-gtk-gtk-h-means]] — if gtk-3.0 becomes a default
include root, `GTK3_INC` disappears and this ticket gets simpler, not moot: the
assertion is still what turns a silent wrong-version build into a diagnostic.
