---
track: N
prio: 65
type: bug
---

# A bound METHOD passed to a string parameter compiles, and produces garbage

```python
tk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
```

with `command: AnsiString` on the callee. NilPy compiled it: the bound-method
value (a `{code, receiver}` pair) was coerced into the string parameter, and the
callee passed that on as a Tcl script. Tk then evaluated garbage on every scroll
update — the symptom was a HANG inside `root.update()`, four layers from the
cause, with no diagnostic anywhere.

Passing a callable where a string is declared is a type error in any reading of
the language. It must be REFUSED at the call site: the project's own rule is
that a gap fails loudly rather than doing something silently wrong, and this one
is worse than most because the wrong value only surfaces inside the event loop.

Related, and already handled in the façade rather than here: the tkinter surface
now takes those options as `Variant` and wires them the way CPython's tkinter
does ([[feature-lib-tkinter-callable-options-with-args]]). That fixes the ONE
library; the frontend hole is still open for every other string parameter in
every library.

## Repro

```python
def f(s: str) -> str:
    return s

class C:
    def m(self):
        return 1

c = C()
print(f(c.m))     # compiles; prints garbage
```

## Gate

`make test-nilpy` with a `{%FAIL}`-style case: passing a bound method (and a
plain def) where a `str` parameter is declared must be a compile error naming
the parameter.
