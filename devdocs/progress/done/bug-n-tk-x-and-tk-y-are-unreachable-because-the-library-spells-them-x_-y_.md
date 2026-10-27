---
track: N
prio: 40
type: bug
---

# `tk.X` / `tk.Y` are unreachable because tkinter.pas spells them X_ / Y_

Found building songformatter (2026-10-27, peer session): `fill=tk.X` reported
"no member X came of the qualifier tk". Pascal folds case, so tkinter.pas
declares X_ and Y_. PyMapReservedMember is a fixed list of reserved words, and
adding X there would rename `m.x` on every user module.

**Fix.** The NilPy qualified-member arm asks the unit instead. When it declares
nothing called `name` but does declare `name_` as a constant, the underscored
spelling is taken. The rule is plain-first, as the reserved-word arm beside it
is. A one-character 'x' is a char constant and lives in the symbol table, so
both tables are asked.

Test: examples/tk/tk_x_and_y_constants.npy (compiled, not run; checked under
Xvfb by hand: prints `x y both`).
