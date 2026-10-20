---
track: N
prio: 20
type: bug
---

# A method fetched with getattr() crashed when called without its defaults

Reported 2026-10-20 by neo-73. `getattr(c, "f")(1.0)` against
`def f(self, x, limit=50)` compiled cleanly and died with SIGSEGV (rc 139) on
x86-64 and aarch64. `c.f(1.0)` and `m = c.f; m(1.0)` were fine, as was a
getattr call that wrote every argument.

**Cause:** the runtime getattr path (pydynattr_get's method-as-value arm)
built the bound pair with `pybound_new_star`, which carries no PYSIG record.
The call bridge fills omitted parameters only from that record, so it entered
the two-parameter body through a one-argument call. `m = c.f` gets its record
at compile time.

**Fix:** take the method's PYSIG record from its RTTI (the extra word after
the kinds and names, RTTI_METH_FLAG_HASSIG), the same record pyeval's
reflected call reads, and build the pair with `pybound_new_sig`. Keyword
arguments through a getattr'd method now bind by name as well.

Test: `test_nilpy_getattr_method_value_fills_its_defaults` (python3's output;
also matches on aarch64 under qemu).
