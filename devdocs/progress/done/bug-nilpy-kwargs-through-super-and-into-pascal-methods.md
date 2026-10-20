---
track: N
prio: 30
type: bug
---

# `**kwargs` through super().__init__, and `**d` into a Pascal method

Found 2026-10-20 with Vloot's `class ModernProgress(tk.Canvas)`, which calls
`super().__init__(parent, height=h, bg=bg, highlightthickness=0, **kwargs)`.

- super()'s argument loop had no star handling: "expected expression" at the
  `**`. From the first keyword, when a `**` follows, the tail now folds into
  one mapping (PyParseKwTailIntoMapping) and fills the base's slots by name,
  as at an ordinary method call.
- `**d` into ANY Pascal method or constructor whose string parameter has a
  default crashed in the variant runtime, before the call, even with an empty
  dict (`cv.configure(**d)` on a tk.Canvas too). DefaultArgValueNode tags the
  default literal with the parameter's managed string kind; boxed into the
  star slot's variant that crashed. PyStarSlotDefault retags it with the plain
  literal kind first. Both star expanders take it.

Tests: test_nilpy_super_init_forwards_kwargs (CPython output),
test_nilpy_double_star_into_a_pascal_method_with_a_string_default.
