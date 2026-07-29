---
track: N
prio: 45
type: bug
---

# `print` writes each argument as it goes, so an exception mid-list leaves partial output

```python
try:
    print("label =", str(3 % 0))
except:
    print("label = ERR")
```

CPython prints `label = ERR` once: it evaluates every argument BEFORE print
emits anything, so the ZeroDivisionError happens with nothing written yet.

pxx prints `label = label = ERR` — the first argument is already on stdout when
the second one raises, and the handler's own print then appends.

Observed across the whole operator sweep once division by zero became catchable
(previously the process died before the difference could show). Every diverging
line has the doubled prefix, which is how it was noticed.

Low severity in isolation, but it makes a program's output depend on WHERE in
an argument list a failure occurred, and it defeats the usual `try: print(...)
except: print(fallback)` shape.

Fix direction: evaluate all of print's arguments into temporaries, then emit.
That is also what `sep=`/`end=` will want when they land
(`print sep= is not supported yet` today).

## Gate

`make test-nilpy` + self-host byte-identical, plus a print whose second
argument raises, under a handler that prints a fallback.
