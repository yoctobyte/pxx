---
track: N
prio: 20
type: bug
---

# `w.bind(seq, lambda e: ...)` on an untyped widget segfaulted

Found 2026-10-20 building Vloot's GUI (neo-73's project). `clickable(widgets,
...)` binds each widget in a loop: `w.bind("<Enter>", lambda e: ...)`. The
native build died with SIGSEGV in PXXStrConcat as the window opened.

**Cause:** `w` has no static class, so the call goes through runtime
dispatch, and PyPickOverloadByArgTypes picks among the same-arity overloads
`bind(sequence, script: AnsiString)` and `bind(sequence, callback: Variant,
add='')`. A lambda is `tyPointer`, which scored 0 against both, so the first
declared overload (the Tcl script string) won and the lambda's pointer was
concatenated into a Tcl command.

**Fix:** PyOverloadArgTypeScore now takes a point off a STRING parameter that
is handed a pointer (a lambda or bound callable) or an object. This mirrors
the existing rule for a class parameter handed a scalar. The Variant overload
wins.

Test: examples/tk/sidebar_cards_and_hover_rows (row tksbar26).
