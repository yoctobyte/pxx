---
track: N
prio: 30
type: feature
---

# tkinter: load libtk at run time, so a Tk program starts without it

lib/pcl/tk.pas imports Tcl/Tk with `external 'libtk8.6.so.0'`, so the binary
names libtcl8.6 and libtk8.6 as required libraries and does not start at all
on a box without them. A program that falls back to a text interface (Vloot:
`except ImportError` / `except tk.TclError`) can only fall back when the
library is present but no display is. Loading Tcl/Tk with dlopen at the first
Tk() and raising TclError when it is missing would give one binary for both.
The dlopen path exists (dynlibs, -dPXX_DYNLIB_LIBC) but is opt-in and verified
on x86-64 only; aarch64 would need checking.

**Seen in the field 2026-10-20 (neo-73):** the Vloot binary built at
add6990535 fails on via (real aarch64) even with `--console`, with "error while
loading shared libraries: libtk8.6.so.0: cannot open shared object file". via
has libtcl8.6 but not libtk8.6. A headless or lightly equipped fleet box
therefore can't run the full-app binary in any mode. Raised to prio 30 because
this is what makes one binary run everywhere.
