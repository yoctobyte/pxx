---
track: N
prio: 55
type: feature
---

# NilPy: `@property` and `@x.setter` inside a class

Hangs off [[feature-nilpy-corpus-uforth]]. uforth's wall as of 2026-07-20, at
uforth.py:384, after float()/None-local landed.

```python
@property
def base(self) -> int:
    b = self.memory[SYS_BASE_ADDR:SYS_BASE_ADDR + 8]
    return int.from_bytes(b, "little", signed=True)

@base.setter
def base(self, value: int) -> None:
    ...
```

Currently `PyParseClass`'s body loop errors on any `@` inside a class:
`unsupported decorator inside class (only @dataclass on classes)`
(pyparser.inc, search that message).

## Census

Exactly **2 properties, each with a getter AND a setter** (`compiling`,
`base`), plus the 11 `@dataclass` uses that already work. Both map a Python
attribute onto uforth's byte memory, so both directions are genuinely used —
a read-only implementation does not get past this.

## Recommended shape — reuse Pascal's real properties

The dialect already has class properties, and the shared parser already
dispatches a named property's READ and WRITE through its accessor methods
(`FindUProp` in parser.inc, e.g. the `self.x` path). So the frontend only has
to REGISTER one:

- `AddUProperty(ci, noff, nlen, tk, recId)` (symtab.inc:526) creates it.
- `UPropReadMOff/MLen` and `UPropWriteMOff/MLen` name the accessor METHODS —
  they store a name offset into `TokChars`, resolved later by `FindUMeth`.

That gets `self.base` and `self.base = v` working with no new lowering.

## The one real obstacle — the name collision

Python names the getter and the setter **both** `base`. Pascal needs two
distinct methods, so the accessors must be mangled (e.g. `base` ->
`__prop_get_base` / `__prop_set_base`) and the property itself keeps the plain
name `base`.

`PyParseMethod(ci)` takes no name override and reads the name from the token
stream, and `PyRegisterClassMembers` (the member PRE-PASS, pyparser.inc:4795)
independently registers method names the same way. **Both** have to learn the
mangled name or they will disagree — the pre-pass registering `base` twice is
what makes the second `def base` collide today. Threading an optional
name-override through those two is the bulk of the work; the property
registration itself is a few lines.

Do NOT try to avoid the mangling by registering a method `base` and a property
`base` together: the getter/setter pair still collides with each other, and
member lookup order between properties and methods becomes load-bearing.

## Gate

`make test-nilpy` green with a `.npy` case diffed against CPython covering
BOTH directions (a read and a write, and a write whose effect is observed
through a later read) + `--tier quick` + self-host byte-identical +
`make fpc-check` clean relative to HEAD.
