---
track: U
prio: 60
type: decide
blocked-by: []
summary: "Eight lib/rtl Pascal units share a name with a Python stdlib module (classes io json math random re strings types). A NilPy `from types import X` silently binds to Pascal's types.pas; `from classes import X` fails inside Pascal's classes.pas with a message about `Delete`. What should a NilPy import do when the name resolves to a unit that is not a NilPy module?"
---

# NilPy imports that collide with a same-named Pascal RTL unit

> **DECIDED by the user, 2026-08-19. None of options 1-4 — the answer is a rule that
> supersedes them, and it supplies the escape hatch the recommendation deferred.**
>
> **The rule:**
> 1. **A bare, extensionless import is PYTHON.** `import math` / `from types import X`
>    resolve to a Python module only — `.py` or `.npy`.
> 2. **Importing another language requires an EXPLICIT EXTENSION** — `math.pas`, `math.c`.
>    That is what makes a Pascal or C unit reachable from NilPy at all.
> 3. **A residual collision is solved by `import ... as ...`** — importing both `math.pas`
>    and `math.c` leaves `math.xyz` ambiguous, and the alias is the answer. No new syntax.
>
> **User's note on fallout:** tests may rely on today's behaviour; rewrite them. *"Won't
> affect any functionality, if all is well."* That last clause is the acceptance criterion,
> not a hedge — see the scope finding below, which is where it stops being true.
>
> This is better than the recommended 1+4 for the reason the recommendation itself named:
> option 1's cost was that a NilPy program wanting a Pascal unit *"loses the ability to say
> so"*, and the ticket parked an escape hatch until something asked for it. Rule 2 **is**
> that escape hatch, so the cost never lands.
>
> Work re-filed as **[[feature-a-a-bare-nilpy-import-means-python-and-another-language-needs-its-extension]]**.
> Recording the decision alone is not enough — `ready`/`next` do not read decisions.

## SCOPE FINDING — the eight units are THREE populations, not two (coordinator, 2026-08-19)

Measured before re-filing, because the decision's fallout is larger than "rewrite the
tests" and the implementer must not discover this halfway.

**Some of those Pascal units ARE the Python module, deliberately.** Their own headers say
so:

    lib/rtl/re.pas   { Python's `re` module for the Nil-Python frontend.
    lib/rtl/io.pas   { Python's `io` for the Nil-Python frontend — the in-memory buffers.

and `math` / `json` were reported behaving correctly as Python's. So the population splits
three ways:

| population | example | what rule 1 must do |
| --- | --- | --- |
| Pascal unit that **is** the Python module | `re`, `io`, and apparently `math`, `json`, `random` | bare name **must keep resolving** |
| genuinely-Pascal unit sharing a name | `classes`, `types`, `strings` | bare name **must stop resolving** — this is the bug |
| `mimic_*` shim | `mimic_codecs` | already handled by the prefix path (`parser.inc:33743`) |

**So "bare name = Python" cannot be implemented as "reject anything written in Pascal".**
The distinction is not the source language, it is *what the unit is FOR* — and today that
intent is recorded only in a comment, in two of the units, in prose. The implementer must
first make it machine-readable: either rename the category-1 units into the existing
`mimic_` convention, or give them an explicit marker. **Pick one and apply it to all of
them** — a rule enforced for some members of a category is the split this repo keeps paying
for.

**Consequence for the user's acceptance criterion:** "won't affect functionality if all is
well" holds for populations 2 and 3, and holds for population 1 *only after* it is
classified. **21 `.npy` tests import these names**; most are population 1 and must keep
working unchanged. A test rewrite is correct for the `classes`/`types`/`strings` shape and
would be a REGRESSION if applied to `math`/`re`/`json`.

## IMPLEMENTATION NOTE — `import math.pas` collides with Python's own dotted syntax

Flagging, not relitigating: in Python `import a.b` means *submodule `b` of package `a`*
(`import xml.dom`). So `import math.pas` is syntactically the shape NilPy already uses for
packages, and the parser has a dotted-import path (`PyImportIsConsumedOnly` was fixed today
to test the FULL dotted path, not just its root).

Workable, because the language-extension set is small and known (`pas`, `c`, later `zig`,
`rs`): treat a trailing component in that set as a language selector rather than a submodule.
The residual risk is a real Python package with a submodule literally named `c` or `pas`.
**If the implementer judges that risk unacceptable, that is a genuine second fork** — file
`decide-*` for the spelling rather than inventing one.

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

## USER, 2026-08-19, on both flagged forks: **"that's a matter of whitelisting"**

Settles the two open questions above. Neither is a design fork; both are a curated list.
**No `decide-*` follow-up is needed — do not file one.**

**1. Which trailing component selects a language.** A whitelist of language extensions
(`pas`, `c`, later `zig`, `rs`). `import math.pas` reads as a language import because `pas`
is on the list; `import xml.dom` stays a submodule import because `dom` is not. The residual
risk I raised — a real Python package with a submodule literally named `c` or `pas` — is
accepted as the cost of a closed, short, known list.

**2. Which `lib/rtl` units ARE the Python module.** Also a whitelist — **not** a rename.
This is the more consequential half of the answer, and it is the cheaper design:
`re`, `io`, `math`, `json`, `random` stay where they are and are listed as serving their
Python spelling; `classes`, `types`, `strings` are absent from the list and therefore
unreachable by a bare import. **So the 21 `.npy` tests that import these names do not churn**
— the population-1 tests keep working untouched, and only the genuinely-Pascal collisions
change behaviour. That is what makes the user's "won't affect any functionality, if all is
well" hold.

**Precedent, which is why this fits rather than being a new mechanism:** the per-library
config is already *a curated define set in the compiler source*
(`PasApplyMimicDefines`, `lexer.inc`), not a file on disk. A curated whitelist in source is
the established pattern here, so this adds a list to an existing shape rather than inventing
one.

**The one discipline the whitelist inherits:** it is now the machine-readable record of an
intent that currently lives in prose, in a comment, in two of the eight units. When a new
`lib/rtl` unit is written to serve a Python module, adding it to the list is part of writing
it — otherwise the bare import silently stops resolving and the failure appears far from the
cause. Say that at the list's definition site, not in a ticket.

