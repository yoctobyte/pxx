---
prio: 70
type: bug
track: N
summary: "SEGFAULT, and a COMPILER crash under -g: a class whose method parameter name matches the CLASS name still mis-resolves on the FIELD path. `class A` + `def __init__(self, a): self.a = a` + a tuple return crashes. Same family as the fixed return-inference bug; that fix did not cover this route."
---

# The class/parameter name collision still crashes on the FIELD path

- **Type:** bug (NilPy — hard crash, both at run time and in the compiler) — **Track N**
- **Filed:** 2026-08-04, Track A+N overnight.
- **PRE-EXISTING**, verified against `stable_linux_amd64/default/pinned` and
  against `a87e8a224`.

## CORRECTION — this ticket was first filed with the wrong cause

It was originally titled "a tuple of a field from an omitted default segfaults",
with a seven-row narrowing table concluding that four conditions were needed: a
constructor, an omitted defaulted variant parameter, a field, and a tuple return.

**Three of those four were coincidence.** The narrowing varied the structure and
never varied the NAMES — the repro used `class A` with a parameter `a`, and
identifier lookup here is case-insensitive. That is the exact confound this
ticket's sibling
([[bug-nilpy-a-local-named-like-a-class-is-typed-as-that-class]]) carries an
explicit warning about, reproduced by the same person an hour later. Recorded
rather than quietly rewritten, because the lesson is the point: a narrowing table
is only as good as the variable you forgot to vary.

The default is irrelevant. Renaming either the class or the parameter fixes it.

The FILENAME still says `tuple-of-a-field-from-an-omitted-default` and is
deliberately left alone: `e1e43a5e6`'s commit message cites that slug, and commit
messages cannot be corrected. The title and body above are the truth; the slug is
historical.

## Repro

```python
class A:
    def __init__(self, a):
        self.a = a
    def show(self):
        return (self.a, 2)
print(A(1).show())
```

```
CPython:  (1, 2)
pxx:      Segmentation fault (core dumped)
```

And the COMPILER itself dies on the same input with `-g`:

```
$ pascal26 -g repro.npy out
Segmentation fault (core dumped)
```

## Narrowing (re-done, varying the names this time)

| variation | result |
| --- | --- |
| `class A`, parameter `a` | **SIGSEGV** (and compiler SIGSEGV under `-g`) |
| `class Zed`, parameter `a` | ok |
| `class A`, parameter `q` | ok |
| `class A` + param `a`, but `return self.a` (no tuple) | ok |
| `class A` + param `a`, ctor only (`print(A(1).a)`) | ok |
| ordinary method `def m(self, a)` returning `a` | ok — covered by the landed fix |
| `class A`, `def __init__(self)` with `self.a = 1` literal | ok |

So it needs the colliding name **on the FIELD path**: a ctor parameter whose name
matches the class, stored into a field, and that field then used somewhere that
copies it as an object — the tuple element being the case found.

## Relationship to the fix that landed

`e8b439e24` fixed the collision in `PyInferDefRetType`: a returned bare ident
that is bound in the def no longer takes its type from a same-named class. That
covers `def h(b): return b` and the ordinary-method row above.

It does **not** cover this route, because the returned expression here is
`(self.a, 2)` — a tuple, not a bare ident — so the guard never applies, and the
bad typing has already happened earlier, when the FIELD was typed from the
colliding parameter. Reading such a field directly is harmless (the value is
right); putting it in a tuple copies it as an object and dereferences a
non-pointer.

## Where to look

The field's type is inferred from the ctor assignment `self.a = a`. Find that
inference (the ctor field scan in `PyRegisterClassMembers` /
`PyRegisterClassFieldsPrepass`) and check whether it types the RHS through a path
that consults `IsClassType` before the parameter. `pyparser.inc:3059` is the site
that does exactly that in `PyInferExprType`, and the landed fix deliberately did
NOT reorder it — it worked around it at the return, because reordering there
makes the shell pre-pass and the body pass answer differently, which is a silent
ABI mismatch. A fix here needs the same token-only discipline; `PyNameBoundInDef`
(added by that commit) is the helper to reuse, given the enclosing def's span.

The `-g` crash is likely the same wrong type reaching the DWARF emitter, which
would then be a second symptom rather than a second bug — but that must be
MEASURED, not assumed. Both crashes appear and disappear together across every
row of the table above, which is suggestive and not proof.

## Gate

`make test-nilpy` + self-host byte-identical. Extend
`test/test_nilpy_local_named_like_a_class.npy` (it already pins the sibling bug)
with the field-path rows, including the `-g` compile as a row of its own so the
compiler crash cannot regress silently.
