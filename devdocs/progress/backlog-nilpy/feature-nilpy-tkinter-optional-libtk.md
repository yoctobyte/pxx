---
track: N
prio: 50
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
