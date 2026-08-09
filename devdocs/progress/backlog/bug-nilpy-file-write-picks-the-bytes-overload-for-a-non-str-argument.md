---
prio: 55
track: N
type: bug
blocked-by: []
---

# `f.write(x)` picks the BYTES overload whenever x is not statically a str

- **Type:** bug (NilPy; valid CPython → uncatchable-looking runtime TypeError) —
  **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a log writer whose helper is
  `def wr(path, t): h = open(path, "w"); h.write(t)`).

```python
def wr(t):
    h = open("p.txt", "w")
    h.write(t)          # CPython: writes;  pxx: TypeError: expected an object argument, got str
    h.close()
```

Measured, at `8070feee2`:

| argument | pxx |
| --- | --- |
| `h.write("literal")` | ok |
| `h.write(str(t))` | ok |
| `h.write(t)` (an unannotated parameter) | **TypeError** |
| `h.write("x" + t)` | **TypeError** |
| `h.write("%s!" % t)` | **TypeError** |
| via a local first (`s = "%s!" % t; h.write(s)`) | **TypeError** |

So the shape that fails is "the argument is not statically an AnsiString" —
which, in an unannotated def, is the ordinary case. `str(...)` around it is the
workaround, and it is exactly the kind of workaround a user cannot guess.

## Cause

`TPyFile` declares

```pascal
function write(b: TPyBytes): Int64; overload;      { declared FIRST }
function write(const s: AnsiString): Int64; overload;
```

and the class-method call site picks by NAME and ARITY, not by argument TYPE —
the known landmine (`project_findproc_by_name_ignores_overloads`, whose arity
half was fixed with `FindUMethArity` while the **type half still bites**). A
statically-str argument happens to land on the right overload; a variant one
takes the first declaration, so the string handle is passed as a buffer object
and pylib raises.

Note the history: the AnsiString overload was ADDED to fix
`bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory`, which was
the same mis-pick with a literal argument. That fix moved the boundary rather
than removing it.

## Shape of the fix

The general repair is overload selection by argument type for class methods —
valuable well beyond `write`, and the honest root. Failing that, the codebase's
own precedent for "the static type is unknown, decide at run time" is the `_any`
suffix used for `startswith`/`endswith` (`pystr_startswith_any`): route a
non-str-typed argument to a Variant-taking entry point that dispatches on the
tag. Do NOT simply swap the declaration order — that re-breaks the bytes case in
the same silent way.
