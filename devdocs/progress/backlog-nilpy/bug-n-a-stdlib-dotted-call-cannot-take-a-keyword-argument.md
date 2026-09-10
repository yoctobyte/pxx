---
slug: bug-n-a-stdlib-dotted-call-cannot-take-a-keyword-argument
track: N
type: bug
prio: 50
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, keywords, diagnostics, lekkerzeilen]
blocked-by: []
summary: "`os.makedirs(d, exist_ok=True)` walls with `undefined variable (exist_ok)` — the dotted stdlib-call table (PyStdlibCallProc / PyParseStdlibCall) takes positional arguments only, and its argument loop parses each one as an ordinary expression, so a keyword's NAME is read as a variable. The message blames the keyword rather than the mechanism, which sends the reader looking for a missing definition. Real corpus site: lekkerzeilen/gauges.py:173. Same shape for os.remove(p, dir_fd=None), open(..., encoding=), and every other stdlib call whose CPython signature has a keyword-only tail."
---

# Measured 2026-09-10, compiler `4d3d006cf973`

```python
import os
os.remove("/tmp/zz", dir_fd=None)
```

```
pascal26:2: error: undefined variable (dir_fd)
```

The table's entries map a dotted NAME onto a pylib proc and
`PyParseStdlibCall` then walks `(` .. `)` calling the ordinary expression
parser per argument. `exist_ok=True` is therefore parsed as the expression
`exist_ok` — a name nothing defines — and the `=` never gets a chance to mean
anything.

# Why the diagnostic is the expensive half

`undefined variable (exist_ok)` is a true statement about what the parser did
and a false lead about what is wrong. A reader greps for `exist_ok`, finds
nothing, and concludes the program is broken — where the program is correct
CPython and the mechanism is the gap. **This is a whole class**: every
CPython stdlib signature with a keyword-only tail hits it, and each one
produces a message naming the keyword.

The cheap half, which is worth doing even if the feature is not: make the
argument loop RECOGNISE `<ident> =` and refuse by name —
`os.makedirs(): this call takes positional arguments only; exist_ok= is not
supported yet`. That is a one-site change and it turns a misleading error into
an accurate one.

# The feature, when someone takes it

Each shim would need to declare which keywords it accepts and in which slot.
`os.makedirs(name, mode=0o777, exist_ok=False)` maps cleanly onto a Pascal
default-parameter list, and `Queue(maxsize=2)` already proves a keyword binds
to a Pascal parameter NAME (lib/rtl/mimic_queue.pas records why the parameter
had to be called `maxsize` and not `n`). So the mechanism exists on the
ordinary call path and this table is the one door that does not use it.

# Boundary, measured

| shape | today |
| --- | --- |
| `os.makedirs(d)` | works (2026-09-10) |
| `os.makedirs(d, exist_ok=True)` | `undefined variable (exist_ok)` |
| `Queue(maxsize=2)` — an ordinary CLASS ctor | **works** |
| `q.put(v)` — an ordinary method | works |

The third row is the one that says this is a table problem and not a NilPy
keyword problem.
