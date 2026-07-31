---
track: N
prio: 35
type: feature
---

# `@staticmethod` and `@classmethod` are rejected

```python
class C:
    @staticmethod
    def s(a: int) -> int:
        return a + 1
```

```
error: Nil Python: unsupported decorator inside class (only ...)
```

A compile error, so nothing computes a wrong answer. `@property` already works,
and `@dataclass` works, so the decorator machinery is there and this is two more
cases.

`@classmethod` needs the metaclass `cls` receiver, which pxx already has
([[project_fpcunit_green_metaclass_self]] — Self as a runtime metaclass hidden
argument); `@staticmethod` is the easy one, a plain proc with no receiver.

Found by the OOP sweep against CPython — dataclasses (including a defaulted
field), `@property`, inheritance and `super()` all matched exactly.

## Recon 2026-07-31 — bigger than "the easy one", not attempted

Mapped the shape rather than guessed: `@property`/`@x.setter` already has the
exact pattern needed — `PyPropAccessorPrefixAt(defIdx)` backward-scans past
blank lines from a `def` token to detect its decorator, called independently
by BOTH the class-member pre-pass and the real `PyParseMethod` body pass
("deliberately... a disagreement between them is a silent ABI mismatch" per
its own comment) — an analogous `PyIsStaticMethodAt`/`PyIsClassMethodAt`
would mirror it directly.

The part that makes this NOT "the easy one, a plain proc with no receiver":
`grep -n "'self'" compiler/pyparser.inc` finds the implicit-`self`-as-param-0
logic duplicated across several sites (`pnames[0] := 'self'` and matching
`if (nparams = 0) and (pnames[nparams] = 'self')` checks at multiple points),
mirroring the SAME two-pass registration shape (`PyRegisterClassMembers`
pre-pass + the real parse) as `@property` — every one of those sites needs
to agree on skipping self for `@staticmethod` and re-pointing it at the
metaclass `cls` for `@classmethod`, the same "miss one site, get a silent
ABI mismatch" risk the property-accessor comment already warns about for a
smaller case. Also unresolved: `@classmethod` dispatch through a SUBCLASS
needs the metaclass-`Self` machinery to carry the actual runtime class, not
just the compile-time one the def was declared on (the ticket's own "class
method in a subclass" gate case) — not verified whether the existing
metaclass-Self plumbing already gets this right or needs its own change.

Sized like a dedicated pass (map every self-as-param-0 site, add the two
decorator-detection helpers, verify subclass dispatch), not attempted this
session given the real risk of a partial/inconsistent implementation across
however many sites actually need it — the same "fixing one and leaving
others is worse than fixing none" risk already documented on
`bug-nilpy-keyword-arg-vs-overload-set`.

## Gate

`make test-nilpy` + self-host byte-identical, plus a static method and a class
method called through the class and through an instance, and a class method in
a subclass.
