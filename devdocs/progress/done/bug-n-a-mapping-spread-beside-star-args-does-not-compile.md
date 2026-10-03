---
slug: bug-n-a-mapping-spread-beside-star-args-does-not-compile
title: a mapping spread beside *args does not compile
summary: >
  `va(1, **d)` on `def va(*a, **kw)` -- and the same into a method -- died as
  "expected expression" at the second '*'; `fn(*xs, **kw)` through a callable
  VALUE was refused by name. The second is what functools.partial's
  `self.func(*self.args, *args, **kw)` is made of. FIXED 2026-10-03
  (frankuser).
track: N
type: bug
prio: 60
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

`f(**{"q": 2})` was first noted as a literal-mapping gap. Measured, it is the
CALLEE that matters: `**d` and `**{...}` both work into a def with `**kw` and
no `*args`, and both fail into one with BOTH collectors.

### Into a def or method collecting `*args` and `**kwargs`

Neither arm took it. The forwarding desugaring (PyStarMixedForwardCall,
PyStarExpandCallArgs) serves a callee WITHOUT a star collector, and the
splice arm takes a single `*`. A `**` operand is now marked PY_ARG_KWSPREAD
in the four argument loops that splice (free def, method, dynamic receiver,
PyParseStarMethodArgs). PyPackStarArgs merges it into the kwargs dict in
source order with any `name=value` beside it, through PyHoistDictMergeAny
(any mapping).

### Through a callable value

PyStarDynCall has no keyword channel, and pyvar_callv_kw takes a
compile-time positional count. The new pyvar_callv_kw_star (pyeval) takes
the star list and reads the count at run time, up to the four slots
pyvar_callv_kw has, with a named TypeError past that. With no keyword left
(an empty `**{}`) it is the plain positional call, so a callable that carries
no parameter names still works.

### Verified

test_nilpy_a_mapping_spread_into_a_star_and_kwargs_def_is_collected (defs,
a method, keywords on both sides of the spread) and
test_nilpy_the_functools_shim_matches_cpython (partial): byte-identical to
CPython under -dPXX_HEAP_DEBUG and on i386, census flat, control trips.
