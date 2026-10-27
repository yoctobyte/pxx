---
track: N
prio: 60
type: bug
---

# A module's `from tkinter import Text` captures `Text` in RTL units compiled after it

Found building songformatter (2026-10-27, peer session). Repro:

    m1.py: from tkinter import Text / def f(): return 1
    m2.py: import configparser / def g(): return configparser.ConfigParser()
    main:  from m1 import f; from m2 import g; print(f()); g()

failed in lib/rtl/configparser.pas:365, "no overload of Assign matches (class,
AnsiString)", and the same for Reset, Eof, Rewrite and Close.

**Cause.** Inside a MODULE, a from-import of a class registers a class-alias row
owned by that module (so importers of the module see it). FindUClassImpl ranks
alias rows in the same scan as class rows, and FindUClassAliasRow scans them
too, but neither asked whether the alias's unit is visible. So
configparser.pas's `var f: Text` bound to tkinter's widget class. The
main-program spelling registers no row, which is why one file never showed it.

**Fix.** UClsAliasVisibleHere (symtab.inc): an alias row is a candidate only in
its own unit or in a unit whose uses rule (DeclVisibleSect) reaches it. Applied
at all three alias scans. The app-side workaround (`var f: TextFile` in
configparser.pas) was not taken.

Test: examples/tk/module_from_import_text_then_configparser.npy (compiled, not
run). Fails to compile on pin v452.
