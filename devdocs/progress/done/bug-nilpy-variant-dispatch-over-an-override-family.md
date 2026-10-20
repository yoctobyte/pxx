---
track: N
prio: 20
type: bug
---

# A variant call over a big override family ran out of dispatch slots

Vloot: `self.page.update()` where Page has nine overriding views, plus dict,
set and tkinter's Widget declaring `update`. The program was refused: "too
many candidate classes to dispatch at runtime".

**Cause:** the candidate scan in PyParseVariantMethod collapses a subclass
into its ancestor only when the ancestor is the current hit. With an
unrelated class hit first (Widget), every sibling override became a
candidate of its own.

**Fix:** a class whose parent also answers to the name is skipped. The parent
is visited in its own turn, and a call through its VMT slot reaches the
override. One override family is one candidate.

Test: test_nilpy_dispatch_over_an_override_family (an unrelated Clock first,
then Page and 18 views; the pin refuses it).
