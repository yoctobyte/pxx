---
track: N
prio: 62
type: feature
status: unfinished
owner: ""
---

# `from enum import Enum` — enum classes are not supported

```python
from enum import Enum

class Color(Enum):
    RED = 1
    GREEN = 2

print(Color.RED, Color.RED.name, Color.RED.value)   # Color.RED RED 1
print(Color.RED == Color.GREEN)                      # False
for c in Color:                                      # iterates members
    print(c.name, c.value)
```

```
pascal26:1: error: import: no unit named enum and no shim mimic_enum
```

Walls visibly at the import, which is the right failure — nothing silent here.

**11 of the neuzelaar corpus's 168 files**, so it ranks behind `@dataclass` (60)
and f-strings (70) but ahead of most of the census
(`feature-nilpy-thirdparty-libraries-as-targets`).

## The shape of the work — NOT just a shim unit

The import error suggests a `mimic_enum` unit would do it. It would not: the
semantics are in the CLASS, not the module. What `Enum` actually means:

- class-level `NAME = value` assignments become **member instances**, not
  ordinary class attributes — `Color.RED` is a `Color`, not `1`
- each carries `.name` (the identifier as a string) and `.value`
- `str()` is `Color.RED`, not `1` — and `repr()` differs again
- the CLASS is iterable, in declaration order
- members compare by identity; two members with the same value are aliases
- `Color(1)` looks a member up BY VALUE, `Color["RED"]` by name

NilPy already registers class-level constants (`PyClsAttr*`) and now generates
dunders for `@dataclass` (`PyEmitDataclassRepr`/`Eq`), so the machinery to
synthesize per-class behaviour from a decorator-or-base marker exists. This is
the same shape of job one level up: recognise `class X(Enum)`, convert the
attribute table into members, synthesize `__str__`/`__repr__`/`__eq__` and make
the class iterable.

`IntEnum`/`StrEnum`/`auto()` are follow-ons, not part of this.

## Gate

`make test-nilpy` + self-host byte-identical. A test diffed against CPython
covering: member access, `.name`/`.value`, `str`/`repr`, `==` between members
and against a bare int, class iteration order, and lookup by value and by name.

---

## DE-RISKED 2026-08-30 (frankwasm): the desugaring is expressible in NilPy today

Before writing any compiler code, the target was measured. Every piece the
ticket's "shape of the work" list needs already works when spelled by hand:

| shape | result |
| --- | --- |
| `class C: RED = 1` — class attr constant | `C.RED` -> `1` |
| class attr holding an instance of ANOTHER class | `.name` / `.value` read fine |
| **class attr holding an instance of its OWN class** | **works** |
| `==` between two instances | identity: `True` / `False`, as members need |
| `__str__` on the member's class | `str(C.RED)` -> `C.RED` |

The third row is the one that decides the design, and it is the one I expected
to fail:

```python
class Color:
    def __init__(self, n, v):
        self.name = n
        self.value = v
    RED = Color("RED", 1)          # its OWN class, inside its own body
print(Color.RED.name, Color.RED.value)   # RED 1
```

So `Color.RED` really can BE a `Color`, which is what makes `.name`/`.value`,
identity `==` and `__str__` fall out of existing machinery instead of needing
new per-member representation.

### What that makes this ticket

A source-level desugaring, synthesised the way `@dataclass` already synthesises
`PyEmitDataclassCtor` / `Eq` / `Repr`:

```python
class Color(Enum):        # from this
    RED = 1
    GREEN = 2

class Color:              # to this
    def __init__(self, n, v):
        self.name = n
        self.value = v
    def __str__(self):
        return "Color." + self.name
    RED = Color("RED", 1)
    GREEN = Color("GREEN", 2)
```

The ticket's judgement that a `mimic_enum` shim "would not do it" is right and
this does not contradict it: the shim would still not carry the semantics, but
the semantics turn out to be reachable from the CLASS machinery that exists,
rather than needing a new member kind.

### Detection, and where it hangs

`isDC` is decided in `PyHoistClassMembers` (pyparser.inc:~35200) by looking
BACK from `class NAME` for a `@dataclass` decorator, and drives synthesis at
**two** sites (`:35868` and `:36071` — the one-line-body path and the normal
one). Enum's marker is a BASE, not a decorator — `Tokens[i+2]='('`,
`Tokens[i+3]='Enum'` — so it is a cheaper test at the same place, and must
reach both sites or the two class-parse paths diverge.

### Still open, and NOT to be faked

Class ITERATION (`for c in Color`) and lookup (`Color(1)`, `Color["RED"]`) do
not fall out of the above — they need a class-level member list and iteration
over the CLASS object rather than an instance. **Whatever lands must refuse
these loudly rather than compile them into something plausible**: a partial
Enum that silently iterates nothing, or looks up the wrong member, is the
silent-wrong-answer class, and it is exactly why the decorator implementation
next door was reverted rather than shipped
([[feature-nilpy-user-defined-decorators]]).

`from enum import Enum` must also stop erroring — but only once the class
semantics are real, since an import that resolves and a base that does nothing
is the same silent failure one step earlier.

## The implementation map — every hook named

Traced end to end before stopping, so the build starts at the edits. Each piece
has an existing analogue in the `@dataclass` path; none of it is novel
machinery, and that is the point.

| # | piece | where | analogue |
| --- | --- | --- | --- |
| 1 | detect `class X(Enum)` | `PyHoistClassMembers` ~`:35200`, where `isDC` is decided by looking BACK for `@dataclass`. Enum's marker is a BASE — `Tokens[i+2]='('`, `Tokens[i+3]='Enum'` — so it is a cheaper test at the same spot | `isDC` |
| 2 | register the synthetic ctor + the `name`/`value` fields | `PyRegisterClassMembers`, the `if isDC and not fieldsOnly` branch at `:33985` | same branch |
| 3 | emit the ctor body `__init__(self, n, v)` | new `PyEmitEnumCtor`, mirroring `PyEmitDataclassCtor` (`:34717`, 55 lines). Note it *requires* piece 2 first — it opens with `FindProc(fullName)` and errors `internal: dataclass ctor not registered` | `PyEmitDataclassCtor` |
| 4 | emit `__str__` returning `X.NAME` | new, mirroring `PyEmitDataclassRepr` (`:35075`) | `PyEmitDataclassRepr` |
| 5 | **wrap each member's initialiser** — `RED = 1` must store `X("RED", 1)` | `PyEmitClassAttrExpr` (`:6681`). It currently does `PyParseBoolExpr; valNode := CurASTNode`; for an enum, build `AN_CALL(ctorPi, AN_ARG("NAME"), AN_ARG(valNode))` instead. This is the same node shape the decorator attempt built by hand, so it is known-buildable | — |
| 6 | make the slot carry the class identity | `PyRegisterClassMembers` `:33178` already types `NAME = Cls(...)` as `tyClass` + `REC_UCLASS_BASE+j`; an enum takes the same arm with `j = ci` | the `NAME = Cls(...)` arm |
| 7 | call both synthesis sites | `:35868` (one-line body) **and** `:36071` (normal body) — `isDC` is invoked at both, and an enum must be too or the two class-parse paths diverge | `isDC` |
| 8 | `from enum import Enum` resolves | the import path that currently answers `no unit named enum and no shim mimic_enum` | — |
| 9 | **refuse** class iteration and `X(1)` / `X["RED"]` | must be a loud error, NOT a plausible compile — see the constraint above | — |

### Why this is being handed over rather than started

It is a genuine multi-session build: nine pieces, each needing a ~60-90s
self-host cycle to verify, and pieces 3 and 4 are 50+ lines of emitter each. The
value already banked is the part that would otherwise be re-derived — the
measurement that `Color.RED` can BE a `Color`, which decides the whole design,
and this hook list. Starting the build now and abandoning it midway would leave
the worst of both: a half-synthesised class and no map.

Nothing is applied. `git status` is clean; this ticket is the only artifact.
