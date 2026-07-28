---
track: N
prio: 70
type: bug
---

# A class attribute holding an INSTANCE crashes when traversed

Pre-existing (reproduces on `stable_linux_amd64/default/pinned`), and nothing to
do with nested classes — it surfaced beside them.

```python
class Inner:
    NORMAL = "Normal"

class Outer:
    mode = Inner()            # a CLASS attribute holding an instance
    def get(self):
        return self.mode.NORMAL

print(Outer().get())
```

CPython prints `Normal`. pxx **segfaults** — silently, at run time; it compiles
clean.

Declaring and instantiating is fine (`mode = Inner()` on its own, never read,
runs); it is the TRAVERSAL `self.mode.NORMAL` that crashes, so the attribute
almost certainly holds something that is not a usable instance handle — the
class-attribute initialiser stores it before the class is fully formed, or
stores the wrong thing.

## Where it bites

songformatter's `render_backend.py` declares reportlab's attribute namespace
this way:

```python
class _BlendModes:
    NORMAL = "Normal"
    MULTIPLY = "Multiply"
blendmode = _BlendModes()
```

and `convertrawtext.py` reads `canvas.blendmode.<name>`. So the file COMPILES
and the read would crash at run time.

## Gate

`make test-nilpy` plus a `.npy` that traverses a class attribute holding an
instance, diffed against CPython — and the same through a nested class, which
is the shape that surfaced it.

## Narrowed 2026-07-28

Splitting the traversal shows the fetch is fine and the SECOND hop is what
dies:

```python
class Inner:
    NORMAL = "Normal"
class Outer:
    mode = Inner()
o = Outer()
m = o.mode
print("got attr")     # prints
print(m.NORMAL)       # SIGSEGV
```

So `o.mode` yields a value that binds and can be assigned, and the crash is in
reading a member OFF that value — i.e. what the class attribute holds is not
recognised as an instance at the second access, rather than being absent. That
also rules out the class-attribute initialiser failing to run at all.

Still reproduces at 287b1b34d.
