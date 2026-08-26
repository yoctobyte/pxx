---
track: N
prio: 70
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

## 2026-08-13 — `@staticmethod` is DONE; `@classmethod` is now a Track U question

Re-measured: `@staticmethod` works (declared, called through the class and
through an instance, with the metaclass slot injected at 0), and
`@classmethod` is refused BY NAME rather than by a parse error, which is this
ticket's own recommendation already applied.

What is left is not work but a decision, so it is filed as one:
[[decide-nilpy-classmethod-cls-binding]]. The short version — the mechanism is
closer than this ticket implies, since `@staticmethod` already injects a hidden
`$clsrecv` at slot 0 and the dispatch already passes A class there. The open
question is WHICH class arrives for an inherited classmethod reached through an
INSTANCE, and that is one measurement away from either dissolving the question
or confirming the silent-subclass hazard. Do not guess it; measure it.


## UNBLOCKED 2026-08-16 — the `cls` semantics question is answered; this is ordinary work now

[[decide-nilpy-classmethod-cls-binding]] is closed as measured rather than
decided. Summary of what it establishes, so this ticket does not have to
re-derive it:

- **Slot 0 already carries the RUNTIME class**, including the hard case (a
  classmethod reached through an instance whose static type is the base).
  `parser.inc:6900-6907` takes it from `__pxxRttiOf(obj)`, with the reasoning
  written at the site. No new machinery, no semantic fork — Pascal
  `class function` and Python `@classmethod` already agree on binding to the
  class the call was made *on*.
- **`cls()` will construct.** Both `k = type(self); k()` and `k = Derived; k()`
  produce a `Derived` today, so the "a `cls` that cannot be called" worry is
  gone. [[bug-n-a-type-name-is-not-a-first-class-value]], cited as the blocker,
  is in `done/`.

So the remaining work is: **name the injected slot-0 parameter `cls` instead of
the hidden `$clsrecv`, and lift the by-name refusal** of `@classmethod`.

Carry the existing warning across unchanged: `pyparser.inc:28884` injects
`$clsrecv` in **both** passes and says a disagreement between them is a silent
ABI mismatch rather than an error — which is why `PyIsStaticMethodAt` is one
function asked twice. The named form must be injected in both places on exactly
the same condition.

Suggested gate: the four-way call — `Base.make()`, `Derived.make()`,
`Derived().make()` through a `Base`-typed name, and a variant receiver — each
answering the class the call was made on, diffed against CPython.
