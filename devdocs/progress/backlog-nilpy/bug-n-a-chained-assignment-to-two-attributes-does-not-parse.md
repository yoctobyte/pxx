---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`self.a = self.b = n` -- a chained assignment whose targets are ATTRIBUTES -- does not parse: `expected newline after statement`, pointing at the second `=`. The module-level form `a = b = 3` parses and runs correctly, so the chain itself is understood; it is the attribute target that is not. Reproduces on the pin and at the tip. lekkerzeilen chart.py:184 (`self.width = self.height = max(1, int(pixels))`). Found once the field-inference blocker ahead of it was fixed, which is what made the line reachable."
status: backlog
owner: —
---

# A chained assignment to two attributes does not parse

## The repro

```python
class C:
    def __init__(self, n):
        self.a = self.b = n     # pascal26:3: expected newline after statement

c = C(4)
print(c.a)                      # CPython: 4
print(c.b)                      # CPython: 4
```

```
near: . width = self . height >>> = max (
```

## The control that says where the gap is

```python
a = b = 3
print(a)      # 3
print(b)      # 3
```

That compiles and prints `3 3`, on the pin and at the tip. So the chain is
parsed at module level and the statement parser knows the shape; the failure
is specific to a target that is an attribute reference rather than a name.

## Why it surfaced now

It sits at `chart.py:184`, behind `self.x0, self.z0 = cx - half, cz - half` at
:191 -- and the field-inference pre-pass runs BEFORE the statement parser, so
:191 was reported first and :184 was never reached. Fixing the pre-pass gap
(bug-n-a-field-assigned-from-a-bare-local-has-no-inferable-type) unmasked it.
The two are independent; neither is a cause of the other.
