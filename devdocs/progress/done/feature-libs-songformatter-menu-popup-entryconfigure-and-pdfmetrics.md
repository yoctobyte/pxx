---
track: B
prio: 30
type: feature
---

# Library gaps songformatter hit: Menu.tk_popup, Menu.entryconfigure, pdfmetrics.getRegisteredFontNames

From the songformatter session's build report (2026-10-27); the patch was
written there and applied as is:

- lib/pcl/mimic_reportlab_pdfbase_pdfmetrics.pas forwarded only stringWidth, so
  `pdfmetrics.getRegisteredFontNames()` was "no member". It now forwards it
  (the function already existed in mimic_reportlab_pdfbase).
- tkinter Menu.tk_popup(x, y): Tk's own popup helper.
- tkinter Menu.entryconfigure(index, label=, state=): the index may be an entry
  LABEL, which is how the app calls it (`menu.entryconfigure("Save", state=...)`).
- Widget.withdraw() and Widget.state() (`wm withdraw` / `wm state`), for the
  hidden-root idiom `tk.Tk().withdraw()`. Checked against CPython under Xvfb.
