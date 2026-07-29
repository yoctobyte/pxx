---
summary: "nilpy: calling a method that does not exist compiles and SEGFAULTS instead of erroring"
type: bug
track: N
prio: 70
---

# nilpy: an unknown method call compiles, then crashes

- **Type:** bug (Nil-Python frontend, method resolution) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26, adding [[feature-nilpy-configparser]].

## Severity

A typo, or any method the shim does not have, produces a binary that SEGFAULTS at
runtime. No compile error, no runtime message. That is the worst failure class we
have, and it is trivially reachable — every misspelled method name hits it.

## Repro

```python
from configparser import ConfigParser
cfg = ConfigParser()
cfg.no_such_method_at_all("x")
print("reached")
```
```
ok: /tmp/unk  [code=829866B ...]      <- compiles clean
Segmentation fault (core dumped)      <- exit 139, nothing printed
```

The call is emitted against a target that was never resolved, so control transfers
to whatever the slot holds.

## Related, same shape

A method whose NAME is a Pascal keyword has the same outcome, and this one bites
pure Pascal too:

```pascal
type T = class
  constructor Create;
  procedure set(x: Integer);   { accepted here }
end;
...
t.set(5);                      { compiles; segfaults }
```

So `set` cannot be used as a method name, which matters because Python's
`ConfigParser.set` is exactly that. lib/rtl/configparser.pas spells it `set_` for
now, meaning `cfg.set(...)` from Python still does not work — songformatter's
settings.py uses it.

## Resolved 2026-07-29 (commit 80871015b)

1. An undeclared method CALLED on a declared class is now a compile error naming
   both — `Nil Python: ConfigParser has no method no_such_method_at_all`. A
   dynamic attribute holding a callable still works: the refusal only fires when
   nothing in the module ever writes `.name =` (or calls setattr), so the name
   cannot be one.
2. Both keyword cases were already fixed by the time this was picked up and are
   re-verified here: `cfg.set("s","k","v")` reaches configparser's `set_` through
   the trailing-underscore mapping, and a Pascal `procedure set(x: Integer)`
   declared, called and printed correctly.

## Two fixes

1. **An unresolved method must be a compile error** naming the class and method.
   This is the important one.
2. Then decide how a Python name that collides with a Pascal keyword reaches its
   method: mapping the call `.set(` to a `set_` member is the smallest rule, and
   would let shims keep Python's spelling for `set`, `type`, `end`, `not`.

## Gate

`make test-nilpy` green with a `.npy` case asserting the unknown-method call is
REJECTED at compile time, + `--tier quick` + self-host byte-identical.

## Scope re-measured 2026-07-28

The PASCAL halves of this ticket are already fixed; what remains is NilPy-only.

- An unknown method on a statically-typed Pascal receiver is a compile error:
  `t.NoSuchMethod(5)` gives `"NoSuchMethod": no such member on this
  record/class`, naming the member as fix (1) asked.
- A method NAMED `set` works end to end in Pascal — declared, defined and
  called (`t.set(5)` prints), so the keyword-collision half of fix (2) is gone
  on that side. `lib/rtl/configparser.pas` can carry Python's spelling now;
  whether `cfg.set(...)` reaches it from NilPy is the frontend question below.

Still reproduces, and still Track N: a call on a DYNAMIC (variant) receiver,
which is what every NilPy object is. `c.no_such_method_at_all("x")` on a NilPy
class instance compiles clean and segfaults with nothing printed. The check has
to happen where the dynamic dispatch is lowered, not in the Pascal member
lookup that already rejects the static case.

## Log
- 2026-07-29 — resolved, commit 80871015b.
