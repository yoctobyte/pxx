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

---

## MEASURED 2026-08-16 — the premise is wrong, and there is a real bug hiding behind the cosmetic question

### 1. CPython injects a DICT, not a module object

The ticket's fork rests on: *"it injects the builtins module object, and NilPy
has no module objects — so honouring the letter of it means choosing a value
that is not what CPython has there."* Measured, that is not what happens.

```python
d = {}; exec("x = 1 + 2", d, d)
type(d["__builtins__"]).__name__      # 'dict'      <- not 'module'
d["__builtins__"] is builtins.__dict__ # True       <- by IDENTITY
len(d["__builtins__"])                 # 157
d["__builtins__"]["len"]               # <built-in function len>   (subscript WORKS)
```

Same answer at module level, inside a function, in `__main__`, and in an
imported module. The *module* form only appears as `__main__`'s own
`__builtins__` when run as a script — a different object in a different place,
and not what `exec` puts in a fresh globals dict.

So there is **no module-object obstacle**, and the ticket's stated reason for
preferring option 1 over option 3 does not exist. NilPy also already has
first-class builtin values — `f = len; f([1,2,3])` compiles and answers 3 — so
a name→builtin dict is representable.

### 2. Two behaviours any implementation must match (neither is in the ticket)

- **Globals only, never locals.** `exec("y=1", g, l)` puts `__builtins__` in
  `g` and leaves `l` as `{'y'}`. pxx today leaves `g` **empty**, which is a
  sharper visible difference than the ticket's single example: a caller doing
  `if not g:` branches differently.
- **Do not overwrite.** `exec("z=1", {"__builtins__": {}}, ...)` leaves the
  caller's empty dict in place. CPython injects only when the key is absent.

### 3. The finding that matters: restricted exec is silently ignored

That non-overwrite rule exists to serve an idiom people actually write:

```python
d = {"__builtins__": {}}
exec("n = len([1,2,3])", d, d)
```

| | result |
| --- | --- |
| CPython | **`NameError`** — `len` is not resolvable |
| pxx | **`n = 3`** — resolved anyway |

This is not a key-enumeration difference. It is working CPython code taking a
different path, and in the direction where the author's explicit instruction
(resolve names against *this* mapping) is silently discarded. Under NilPy's
upward-compatibility contract that is a **defect**, not a dialect choice — and
per the compat escape rule, a finding that means silent wrong behaviour is
promoted to a `bug-` ticket in the owning lane rather than parked as parity
work. Filed: [[bug-n-exec-ignores-a-caller-supplied-builtins-mapping]].

Stated honestly: CPython's restricted exec is **not** a security boundary
(`().__class__.__bases__` and friends escape it), so this is not a sandbox-hole
claim. The point is narrower and still solid — the name-resolution *behaviour*
is well-defined, observable, and relied on for evaluating config/template
expressions in a controlled namespace.

## What this does to the fork

The ticket asks one question; the measurement shows it is two, and they separate
cleanly at very different costs:

- **Producing** a builtins dict when the caller supplied none — the cosmetic
  half. Needs an enumerable table of the builtin namespace, which is the real
  work in option 3, and CPython's value being `builtins.__dict__` *by identity*
  means a faithful copy would make `d["__builtins__"]["len"] = ...` mutate the
  builtin namespace program-wide. That is a footgun worth NOT importing.
- **Consulting** a builtins mapping the caller DID supply — the behavioural
  half. Needs no table at all: only "when `globals['__builtins__']` is present,
  resolve builtin names through it." This is the half with the real defect
  behind it, and it is much the cheaper of the two.

The ticket treats these as one option and prices the cheap half at the expensive
half's cost.

**Revised recommendation:**

- **The cosmetic key: option 1 stands** (leave it out), now on a better reason
  than the ticket gave. Not "the true value is unrepresentable" — it is — but
  "the faithful value is a live alias to the builtin namespace, and the only
  known demand is `sorted(d.keys())` in a probe." A copy would diverge on
  mutation; the identity would import a footgun. Absence is the honest answer
  until something needs it. **Option 2 is refused outright**: injecting a key we
  then ignore is strictly worse than both — it claims conformance in the
  enumeration while still failing the restricted-exec case.
- **The behavioural half is not a decision.** It is Track N work under the
  upward-compatibility rule, and it is now filed as such.

Reclassify this ticket accordingly: it stays open only as the record of the
cosmetic call, and `decide-` overstates what is left in it.
