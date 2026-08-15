---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A `self.f = Cls(...)` assignment that comes AFTER an if/for in the same method is never recorded as a class field, so the field falls back to dynamic — silently, because a direct call on it still works and only a bound method taken as a VALUE fails"
status: done
owner: agent-an-night
---

# A field constructed after an `if` in the same method loses its class

Found porting [[feature-b-tkhtmlview-in-nilpy]] (Track B), against
`stable_linux_amd64/default/pinned` **v339 / f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**.

## The repro

```python
import tkinter as tk


class Panel(tk.Frame):
    def __init__(self, master):
        if master == None:            # <-- ANY compound statement; `for` does it too
            print("no master")
        self.bar = tk.Scrollbar(self, orient="vertical")
        self.text = tk.Text(self, wrap="word")
        self.bar.config(command=self.text.yview)
```

```
error: Nil Python: Widget.config has no parameter named 'command'
```

`self.bar` is not a `Scrollbar` any more — it is a bare `Widget`, so
`Scrollbar.config(command=...)` is not among the candidate overloads.

**Move the `if` one line down, below `self.bar = ...`, and it compiles.** That is
the whole difference, and it is what makes this positional rather than a façade
or overload problem.

## What it is, precisely

The field-class record is written only for `self.<name> = <Class>(...)`
assignments **up to the first compound statement in the method**. Everything
after it is left dynamic.

Measured, one variable at a time (all on the pinned binary above):

| shape | result |
| --- | --- |
| `if` **before** the field construction | field is dynamic — FAILS |
| `if` **after** the field construction | field keeps its class — ok |
| `for` before it | FAILS (so it is not `if`-specific) |
| a plain call statement (`print("hi")`) before it | ok — **the control**: an ordinary statement does not do this |
| two fields, one before the `if` and one after | only the one after is degraded |
| the degraded field used from ANOTHER method | still degraded — the record is simply never written |

That last row is the one that says this is a *recording* bug, not a flow-sensitive
narrowing: nothing about the `if` could make a field dynamic in a method the `if`
is not in.

## Why it is quiet, and therefore expensive

A **direct call** on the degraded field still works — `self.text.insert("end", x)`
dispatches dynamically and is fine. What breaks is taking a **bound method as a
value**:

```python
self.bar.config(command=self.text.yview)      # the canonical scrollbar wiring
```

So a class can be full of dynamic fields and look completely healthy until the
first callback wiring, which is exactly the shape a widget library is made of.
This is the same failure surface as
[[bug-nilpy-text-class-name-binds-the-rtl-file-record]] — different cause, same
"direct call works, method-as-value does not" tell. If that one's regression
test ([[examples/tk/field_class_identity.npy]]) grew an `if` in front of its
constructions it would catch this too.

## Suggested fix

Whatever walks `__init__` (and any method) collecting
`self.<name> = <Class>(...)` should walk the **whole** statement list, descending
into `if`/`for`/`while`/`try` bodies rather than stopping at the first one it
does not recognise. Note the nested case needs a decision: a field assigned only
inside one arm of an `if` is a field, but two arms assigning different classes
are not one static class — the conservative answer (record it when every
assignment agrees, leave it dynamic otherwise) is the one that cannot make
today's working code worse.

Per `normalise-dont-special-case.md`: grep for the sibling scan before closing
this. `PyRecFromTokenIndex` and the constructor-intercept path were the six sites
the `Text` collision turned out to span; this pre-pass is likely to have the same
shape.

## Not blocking the port

The tkhtmlview port lands anyway, because the natural spelling puts every widget
construction before any conditional (and writes the background default as
`background or "white"` rather than an `if`). Recorded here so the next library
does not lose an afternoon to it.

## 2026-08-15: NOT REPRODUCIBLE as written — and the real defect found beside it

Measured before touching anything, on **the binary the ticket names**
(`stable_linux_amd64/default/pinned` v339, f11e0ed98) as well as HEAD. The
repro compiles on both:

```
$ stable_linux_amd64/default/pinned  <the ticket's Panel repro>
ok: ... [code=2402310B ...]
```

Also tried with the class actually instantiated (NilPy defers method bodies, so
that was the obvious missing ingredient) — still fine on pinned.

The stated mechanism does not hold either. Rebuilt the ticket's own table with
plain classes, where a lost class fails LOUDLY (a keyword argument cannot bind
without the static class) rather than degrading to a dynamic call — `if`
before, `for` before, `try` before, `while` before, assignment inside one `if`
arm, assignment inside BOTH arms, an assignment nested `if`+`for` deep, two
arms assigning DIFFERENT classes, the field used from another method, and a
bound method taken as a VALUE. **All correct on pinned and on HEAD.** So the
field-class record is not truncated at the first compound statement.

Something else in the tkhtmlview port produced that error, and the reduction
lost it. Rather than guess, the variation sweep was widened over the shapes the
port actually uses — and it found a real defect one line away:

```python
tk.Frame.__init__(self, master, background=background)
```

fails on pinned AND on HEAD. Not the `if`, not the field class: **an unbound
method call took no keyword arguments at all**. That is filed, fixed and gated
as [[bug-nilpy-an-unbound-method-call-takes-no-keyword-arguments]], with
[[bug-nilpy-a-static-method-called-on-the-class-takes-no-keyword-arguments]]
for the one row that could not come with it.

It is a plausible cause of the report: the original method very likely wrote
that base-constructor call, whose failure is a parse error in `__init__`, and
the `if` was a coincidence of where the reduction stopped.

Closing as not-reproducible. **If the `Widget.config has no parameter named
'command'` error comes back, reopen with the FULL method rather than a
reduction** — the reduction is what was lost here. The matrix above is a
starting point that has been ruled out.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
