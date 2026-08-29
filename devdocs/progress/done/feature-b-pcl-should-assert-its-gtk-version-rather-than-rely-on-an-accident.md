---
track: B
prio: 30
type: feature
blocked-by: []
summary: "lib/pcl now includes the stock <gtk/gtk.h>, which resolves to GTK2 unless GTK3_INC puts the gtk-3.0 root first. Forgetting the flag fails loudly today only because PCL happens to call a GTK3-only function -- an accident, not a guard. The binding should assert its version."
status: done
owner: frank-b
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

## Resolution (frank-b, 2026-08-29)

### The prerequisite holds — no Track C ticket needed

Measured against the pinned compiler (v393, `1d69760deabe`) before writing any
of the fix, because the ticket is right that it decides the shape:

| probe | result |
| --- | --- |
| bare `#error` | fires, rc=1 |
| `#error` inside `#if 0` | correctly skipped, rc=0 |
| `#if GTK_MAJOR_VERSION == 2` after `#include <gtk/gtk.h>` | fires **without** `GTK3_INC`, silent with |
| `#if GTK_MAJOR_VERSION == 3` | fires **with** `GTK3_INC`, silent without |
| `#elif` (both arms) | correct in both directions |

The `== 2` / `== 3` pair is the point of that table. `#if !defined(X) \|\| X < 3`
alone could not tell "the macro evaluated to 2" from "the header was never
found", and those want different error messages; the 2×2 shows the macro is
genuinely being read. So the obvious fix was available, and the fallback the
ticket describes (a declaration that only parses under GTK3) is not needed.

### The failure is worse than filed, and in an instructive direction

The ticket says a GTK2-compatible consumer "would build silently against the
wrong library". The library is never wrong. `CHeaderStem` maps the `gtk3_c` unit
name to the `gtk-3` stem, so `libgtk-3.so.0` lands in `DT_NEEDED` whatever `-I`
is in effect — only the *headers* follow `-I`. Measured with a consumer whose
whole surface is `gtk_main_quit` (present in both versions): builds clean with
no flag, links `libgtk-3.so.0`.

So the silent outcome is **GTK2 headers against the GTK3 library** — an ABI
mismatch, not a version mixup. With gcc as the oracle:

```
sizeof(GtkWidget)   96 (gtk2 headers)   32 (gtk3)
sizeof(GtkWindow)  240                  56
```

That is worth flagging to whoever owns the prio: this is the silent-wrong-
behaviour class, and it was filed at p30 on the milder reading.

### Both existing "version" guards were decorative — this is the real finding

The ticket says the runtime half "already exists and should stay:
`gtk_version_check` ... asserts `libgtk-3.so.0` **is** and `libgtk-x11-2.0.so.0`
**is not** in DT_NEEDED. That covers the repo's own builds." **It does not, and
could not.** Both are DT_NEEDED checks, and DT_NEEDED does not follow `-I`.

Measured, by rebuilding with the flag removed and a pre-assertion header:

- `tools/gui_suite.sh gtk_version_check` on `test_gtk_ffi`, no `GTK3_INC`:
  builds, `libgtk-3.so.0` present, `libgtk-x11-2.0.so.0` absent — **both
  conditions pass on exactly the state they exist to reject.**
- `Makefile`'s `readelf -d ... | grep -q 'libgtk-3.so.0'` on
  `test_c_gtk3_stock`, `-I` removed: same, passes.

Both were *commented* as asserting the version. That comment is the load-bearing
part of the defect — a check that cannot fail is merely useless, but a comment
saying it covers the version stops the next reader from looking, which is how
this survived to be filed as "PCL should assert" rather than "nothing asserts".
Same family as the accident the ticket is about: a guard that reads like design.

### What landed

- `lib/pcl/gtk3_c.h` — `#if !defined(GTK_MAJOR_VERSION)` / `#elif
  GTK_MAJOR_VERSION < 3` → `#error`, with separate messages for
  "no GTK headers at all" and "resolved to GTK2", each naming `$(GTK3_INC)` /
  `$GTK3_INC` and the `pkg-config` line.
- `test/gtk3stock/gtk3_c.h` — the same assertion. This copy is not redundant:
  it is the shadow header for the one test that gates the stock-header path, and
  that test's own guard was one of the two vacuous ones.
- `Makefile` and `tools/gui_suite.sh` — comments corrected to claim the link,
  which is what they check. Neither recipe changed; the `readelf` lines stay,
  because a correct link is still worth checking, it is just a narrower claim.

### Verified

`test_gtk_ffi`, `test_pcl_click`, `examples/life`, the five `examples/tk/*.npy`
and `test_c_gtk3_stock` all build with `GTK3_INC`; `test_c_gtk3_stock` now
**fails** without it (it silently succeeded before). `test_c_gtk_window` still
links `libgtk-x11-2.0.so.0` — GTK2 stays authoritative, checked rather than
assumed. Self-host fixedpoint converged in 2 rounds.

Nothing here touches what a bare `#include <gtk/gtk.h>` resolves to, so
[[decide-which-gtk-a-bare-gtk-gtk-h-means]] is untouched and this does not
depend on it: the assertion reports whichever answer that fork gets.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
