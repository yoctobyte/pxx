---
slug: bug-n-a-keyword-argument-does-not-bind-when-a-constructor-overload-set-contains-a-zero-parameter-arm
track: N
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, overload, constructor, keyword-args, mimic, lekkerzeilen]
blocked-by: []
summary: "`queue.Queue(maxsize=2)` -- app.py:575's exact spelling -- fails with `Queue() is missing a value for parameter 1, which has no default`, while `queue.Queue(2)` works and the parameter really is named `maxsize`. Measured 2026-09-10 at compiler 61f8a78f8aae with three controls that narrow it: a keyword binds fine on a NilPy-defined class's __init__, on a Pascal shim METHOD, and on a Pascal constructor overload set whose arms all take at least one argument (`array.array(tc=\"h\")` resolves against Create(tc)/Create(tc,init) and works). The one shape that fails is an overload set containing a ZERO-PARAMETER arm, where the keyword has to select the other one. NOT the same defect as bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type, which is about which arm is chosen for POSITIONAL arguments; this is about a keyword failing to bind after an arm is chosen. Worked around in mimic_queue by collapsing to one constructor with a default (`Create(maxsize: Integer = 0)`), marked REVERT TO TWO OVERLOADS."
---

# What fails

```python
import queue
b = queue.Queue(maxsize=2)      # app.py:575, verbatim
```

```
pascal26:2: error: Nil Python: Queue() is missing a value for parameter 1, which has no default
```

The shim declared exactly what the message asks for:

```pascal
constructor Create; overload;
constructor Create(maxsize: Integer); overload;
```

`queue.Queue(2)` compiles and runs. The parameter is named `maxsize`. Renaming
it from `n` to `maxsize` changed nothing, which is what sent this to a
measurement rather than to a second guess.

# The three controls, and what each rules out

Measured 2026-09-10, compiler `61f8a78f8aae`, HEAD `d326d8535`.

| probe | shape | result |
| --- | --- | --- |
| `C(maxsize=5)` on `class C: def __init__(self, maxsize)` | NilPy-defined constructor | **works** |
| `q.put(v=7)` into a Pascal shim | Pascal METHOD, not a constructor | **works** |
| `array.array(tc="h")` | Pascal constructor, OVERLOADED — `Create(tc)` / `Create(tc, init)` | **works** |
| `queue.Queue(maxsize=2)` | Pascal constructor, overloaded — `Create` / `Create(maxsize)` | **FAILS** |

So it is not keyword arguments in general, not Pascal callees in general, and
**not overloading in general** — the third row is an overloaded Pascal
constructor whose keyword binds correctly. The first draft of this ticket said
"overloaded constructor" and that was wrong; `mimic_array` refutes it, and it is
the row that stops this being filed against the wrong mechanism.

What separates the failing row from the passing one is that its overload set
contains an arm taking **no parameters at all**, so parameter 1 of "the
constructor" is not a single thing to bind a name against.

**What was NOT measured**, and a fix should establish it rather than assume this
ticket did: whether a zero-parameter arm is precisely the trigger, or whether
the real rule is something broader like "the arms disagree about the name of
parameter 1". Two probes settle it — `Create(a)` / `Create(b, c)` with different
first-parameter names, and `Create` / `Create(a)` where the keyword names `a` —
and neither was run here because the workaround removed the need.

# Why it is not the ticket next door

`bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type`
(prio 55) is about WHICH arm gets chosen when several could take the positional
arguments given — first match by name, ignoring types. This one is about a
keyword failing to bind **after** an arm is chosen; the diagnostic even names
the chosen arm's parameter 1. They may share a cause in the same resolution
path, and if a fix closes both that is a good outcome — but they fail
differently and one is not evidence for the other.

# Workaround in place

`lib/rtl/mimic_queue.pas` declares ONE constructor with a default:

```pascal
constructor Create(maxsize: Integer = 0);
```

which serves `Queue()`, `Queue(2)` and `Queue(maxsize=2)` alike. Marked
**REVERT TO TWO OVERLOADS** in the file, in the style of
`devdocs/dev/track-b-workarounds.md`: it is a shape chosen to sidestep an open
compiler bug, not the shape the code wants.

This is the second shim in two days to collapse a constructor overload set for a
reason that is not about the shim — `mimic_array` did the same thing on
2026-09-09 for the sibling ticket. Two shims cannot both be wrong about how to
write a constructor; the resolution path is.
