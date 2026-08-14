---
track: U
prio: 40
type: decide
summary: "CPython's exec(src, g, l) injects a `__builtins__` key into the globals dict; NilPy does not, because it has no module object to put there. So sorted(d.keys()) after an exec differs. Three options: leave it out (today), inject the key with a placeholder value, or inject a real minimal namespace. The fork is what a program that ITERATES the dict should see."
---

# Should `exec` inject a `__builtins__` key?

- **Type:** decision — **Track U**. Escalated rather than guessed while closing
  [[bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent]], which made `exec`
  bind at all.

## The observation

```python
d = {}
exec("x = 1 + 2", d, d)
print(sorted(d.keys()))
```

| | value |
| --- | --- |
| CPython | `['__builtins__', 'x']` |
| pxx | `['x']` |

Reading `d["x"]` — what essentially all real code does — agrees. The difference
is only visible to a program that ENUMERATES the namespace.

## Why it is a decision and not just work

The governing rule is *default to the reference implementation*, and the
reference injects the key. But it injects **the builtins module object**, and
NilPy has no module objects — so honouring the letter of it means choosing a
value that is not what CPython has there. That trade is the fork:

1. **Leave it out** (today). `d.keys()` is short by one. A program that iterates
   the namespace and does something per entry sees a smaller, cleaner set — and
   silently differs from CPython.
2. **Inject `__builtins__` -> None** (or an empty dict). Key listings match.
   A program that *uses* the value — `d["__builtins__"]["len"]` — gets a wrong
   answer instead of a missing key, which is the worse failure shape.
3. **Inject `__builtins__` -> a real dict of the builtin names.** Matches
   CPython in both key and usable content, at the cost of building that dict on
   every exec and deciding what belongs in it.

My recommendation is **1 (leave it out) plus this ticket as the record**, on the
grounds that option 2 trades a visible absence for an invisible lie, and option
3 is real work with no measured demand. But the reference-compat default points
the other way, which is exactly why this is not mine to settle.

## What would change the answer

A corpus file that iterates an exec'd namespace. None is known — the census
population is `devdocs/dev/python-libraries.md` §7. If one turns up, option 3.

## Recorded meanwhile

`devdocs/dev/nilpy-semantics-divergences.md` carries the row, so the difference
is documented rather than latent.
