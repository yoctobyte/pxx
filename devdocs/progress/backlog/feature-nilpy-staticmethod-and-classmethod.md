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

## 2026-08-09 — @staticmethod IMPLEMENTED; @classmethod still refused, by name

The 2026-07-31 recon called this a dedicated pass over "every self-as-param-0
site". It turned out to be one idea plus two sites, because the recon was
looking for the wrong shape.

### The idea: do not remove the receiver, OCCUPY it

`UMthIsStatic` is Pascal's `class procedure` flag, and every call path in
`parser.inc` that consults it — including the `PyExprMode` arm — already passes
the CLASS as parameter 0. That is what makes the metaclass idiom work. So the
two conventions line up if the static method is registered **with a hidden
receiver at slot 0**, the slot the dispatch already fills, rather than teaching
those paths a third convention. Nothing in `parser.inc` or `ir*.inc` changed.

The body cannot see it: the parameter is named `$clsrecv`, and the implicit-self
handling everywhere is keyed on the literal NAME `self` at position 0 — which is
why the recon's list of `'self'` sites did not actually need editing. A static
method simply never declares one.

It also takes **no virtual slot**: dispatch does not go through the VMT, and
handing it one desynchronises a subclass's override numbering.

### Both traps in this area fired, and both were silent

1. **First attempt made it a `tyClass` receiver.** The call site builds an
   `AN_CLASSREF` for the argument, which reached `IRLowerAddress` and produced
   `IR_UNSUPPORTED` (kind 46). `tyPointer` is the right kind. Loud, at least —
   `--strict-ir` is what made it loud rather than a miscompile.
2. **The pre-pass and the real parse disagreed on the `def` token index.**
   `PyIsStaticMethodAt(TokPos - 3)` should be `TokPos - 4`: `TokPos` sits one
   PAST `CurTok`, which is why the neighbouring `@property` check is `TokPos-2`
   when `CurTok` is the name; with `(` already consumed the tokens run
   `[def][name][(][CurTok]`. Off by one, so only the pre-pass saw the decorator
   and the two passes registered DIFFERENT signatures. **Not an error** — the
   exact silent ABI mismatch `PyPropAccessorPrefixAt`'s own comment warns about,
   reproduced within an hour of reading that warning.

### @classmethod is NOT done and now refuses BY NAME

It needs a real `cls` receiver carrying the RUNTIME class. Treating it as a
static would bind `cls` to the DECLARING class, so `Sub.make()` would build a
`Base` — wrong object, run time, no diagnostic. It gets its own message saying
so instead of the generic "unsupported decorator", which reads like a parser
limitation.

`test/test_nilpy_classmethod_fail.npy` pins that refusal, so "make it parse"
cannot land without making it correct.

### Verified
`test/test_nilpy_staticmethod.npy` against CPython's own output: class- and
instance-reached calls, a static called from an instance method, a subclass
OVERRIDING a static, arity 0/1/2, annotated and unannotated parameters, a static
beside `@property` and `__init__`, a static calling another static, and a class
whose only member is a static. `gate.sh quick` GREEN (self-host fixedpoint +
testmgr quick).

### Remaining
The @classmethod half. Retitle/refile as `feature-nilpy-classmethod` when picked
up; retire the refusal test then.
