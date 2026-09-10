---
slug: bug-n-a-stdlib-dotted-call-cannot-take-a-keyword-argument
track: N
type: bug
prio: 50
status: done
owner: "frankB"
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, keywords, diagnostics, lekkerzeilen]
blocked-by: []
summary: "FIXED 2026-09-10 (frankB). The table's argument loop now asks PyKwArgIndex + PyBindKwArgs — the same pair every ordinary call and every class constructor uses, and this table was the one door that did not. `os.makedirs(d, exist_ok=True)` and `os.makedirs(name=d, exist_ok=True)` both work; `pyos_makedirs` was respelled with CPython's parameter names (name, mode, exist_ok) because a keyword binds by the PASCAL parameter's name. The bind runs BEFORE the arity re-target, so the overload is chosen against the count the callee will actually receive. An unknown keyword now names the DOTTED spelling the program wrote instead of the pylib shim it never mentioned. The urlopen(timeout=) site turned out to be a DIFFERENT door that was not broken — the keyword bound fine and the parameter was an Integer against CPython's float seconds, so the failure was `no overload matches` rather than the timeout refusal that explains itself; now a Double."
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

## FIXED 2026-09-10 (frankB)

The feature, not the cheap half — and the cheap half came free with it, because
the refusal path had to know the dotted name anyway.

`PyParseStdlibCall`'s argument loop now calls `PyKwArgIndex(procIdx, 0)` per
argument and `PyBindKwArgs` after the list. `firstParam` is 0 and not 1: these
are plain procs with no Self in slot zero.

**The bind runs BEFORE the arity re-target, and that ordering is the whole
reason it is safe.** After the bind, `nArgs` is the count of parameters
actually BOUND, so the overload chosen by arity is chosen against the number
the callee will receive. Re-targeting first would resolve the keyword NAMES
against one overload and the call against another — the same class as
`bug-nilpy-keyword-arg-vs-overload-set`, which is what `PyKwArgIndex`'s own
sibling-overload message exists for.

`pyos_makedirs` was respelled `(name, mode = 511, exist_ok = False)`. A keyword
binds by the **Pascal** parameter's name, so a shim's parameters have to be
spelled as CPython spells them; `lib/rtl/mimic_queue.pas` records the same
constraint from the other side, having been refused for calling its parameter
`n`. `mode` is now threaded through to `PyPalMkdir` instead of being hardcoded,
and `pyos_mkdir_one`'s `leaf` parameter was renamed `failIfExists` because the
caller now passes `not exist_ok` and the old name had become a lie.

### The diagnostic half

    pascal26:2: error: Nil Python: os.makedirs() has no parameter named
    'nosuch'. The shim is pyos_makedirs; a keyword binds by the Pascal
    parameter name, so adding the keyword means naming a parameter for it there

The dotted spelling is rebuilt from the tokens before they are consumed, purely
so the message can name what the program WROTE. `pyos_makedirs` is an internal
name the source never mentions — this file already pays for that mistake once,
in the `math.log` intercept, which exists because the generic arity error named
the RTL's `Ln`.

### `urlopen(timeout=)` was a DIFFERENT door, and it was not broken

Worth recording because it looked like the same bug and is filed under the same
line of the corpus. `urllib.request.urlopen` goes through the Pascal
qualified-call path, not this table, and that path handles keywords perfectly
well. The parameter was `Integer` and CPython's `timeout` is a float number of
seconds, which real code writes — `gauges.py`'s `fetch` defaults to `20.0`. So
the failure was

    no overload of urlopen matches these arguments

which says nothing whatever about timeouts, instead of the shim's own careful
refusal explaining that `lib/rtl/http.pas` has no request timeout. Now a
`Double`, tested with `< 0` rather than against the sentinel, because comparing
a Double for equality against a constant works until someone writes the
constant as an expression.

**Two doors, one corpus line, and the second one was a TYPE problem wearing an
overload message.** A fix aimed only at the table would have left gauges.py
walled one line later with a message that named neither the keyword nor the
timeout.

### Effect

`lekkerzeilen/gauges.py` moves :141 -> :173 -> **:174**, `sqlite3.connect` —
`feature-n-the-sqlite3-module-db-api-over-the-c-library`, filed, p65.

Positive control: the previous binary refuses the fixture at line 28 with the
reported `undefined variable (exist_ok)`.
