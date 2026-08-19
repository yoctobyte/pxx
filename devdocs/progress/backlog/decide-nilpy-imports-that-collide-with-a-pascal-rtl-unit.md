---
track: U
prio: 60
type: decide
blocked-by: []
summary: "Eight lib/rtl Pascal units share a name with a Python stdlib module (classes io json math random re strings types). A NilPy `from types import X` silently binds to Pascal's types.pas; `from classes import X` fails inside Pascal's classes.pas with a message about `Delete`. What should a NilPy import do when the name resolves to a unit that is not a NilPy module?"
---

# NilPy imports that collide with a same-named Pascal RTL unit

## The fork

NilPy's unit scope is FLAT, so `import X` in a `.npy` finds `lib/rtl/X.pas`
whether or not that unit has anything to do with Python's module `X`. Eight
names currently collide:

```
classes  io  json  math  random  re  strings  types
```

Most are deliberate and correct — `lib/rtl/re.pas` states in its header that it
IS Python's `re` for the NilPy frontend, and `math`/`json` behave correctly. The
question is what to do about the ones that are genuinely Pascal units:

```python
from types import ModuleType     # -> lib/rtl/types.pas (TPoint/TRect/TDuplicates)
print(ModuleType.__name__)       # error: undefined variable (__name__)

from classes import Foo          # -> lib/rtl/classes.pas
                                 # error: no overload of Delete matches these arguments
```

The second is the shape that makes this worth deciding rather than patching: the
diagnostic names `Delete`, a symbol inside a Pascal unit the program never
mentioned, and there is no path from it back to the import.

## Options

1. **Refuse, naming the collision.** A NilPy import that resolves to a unit
   which is neither NilPy-authored nor a `mimic_` shim errors with *"`types`
   resolves to the Pascal unit lib/rtl/types.pas, which is not Python's `types`
   module"*. Cheap, honest, and turns every instance of this into a
   self-explaining failure. Costs: a NilPy program that legitimately wants a
   Pascal unit by that name loses the ability to say so.
2. **Namespace the lookup.** A NilPy import searches NilPy modules and `mimic_`
   shims first, and only falls back to a Pascal unit when nothing else matches.
   More permissive; the failure mode returns whenever a name exists in both.
3. **Write the shims.** `mimic_types.py` etc., one per collision, so the Python
   spelling gets the Python meaning. Correct in the long run but unbounded, and
   it does not help the next collision that appears.
4. **Do nothing but improve the diagnostic** (see
   [[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]]).

## Recommendation

**1, plus 4.** The refusal is a handful of lines, needs no per-module work, and
is *upward compatible with CPython* in the direction that matters: a program
CPython accepts and runs does not currently work anyway, so refusing it loudly
takes nothing away and stops it failing as a wrong answer or an unrelated
message. 3 then becomes ordinary Track B work that can be done per module as a
corpus needs it, with the refusal naming exactly which shim is missing.

The escape hatch for option 1's cost: if a NilPy program really wants the Pascal
unit, that is what an explicit spelling is for — but nothing has asked for it,
so do not build it before something does.

## Provenance

Found 2026-08-19 by frankonpiler-an while investigating why
`from types import ModuleType` misnamed its diagnostic — the ticket assumed an
unresolved import, and the measurement showed the import resolves, to a Pascal
unit. Filed to Track U rather than guessed at, per the escalate-don't-guess rule.
