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

## 2026-08-04 — the obvious fix was ATTEMPTED and REVERTED; it trades a crash for a WRONG VALUE

Recording the negative result, because it rules out the first thing anyone will
try and it names a second consumer nobody had located.

### What was tried

`pyparser.inc:18126` already carries a fix for the ANNOTATED form of this
collision (`bug-nilpy-str-of-object-segfaults-when-dunder-builds-a-string`): the
RHS is read as a header parameter *before* the type scanners see it, so
`def __init__(self, node: int)` + `self.node = node` types the field `int`
instead of class `Node`.

That fix keys on the parameter having a **type**. `PyHeaderParamType` answers
`tyUnknown` for an UNANNOTATED parameter, so `def __init__(self, a)` falls
straight through to `PyTypeFromTokenIndex`, which maps the ident to `tyClass`
case-insensitively. The obvious completion is to key on it being a **parameter**
instead — skip the class-name reading when
`PyHeaderHasParam(methodStart, j, rhsName)`, letting it fall to the
unannotated-parameter branch that already assigns `tyVariant`.

### It works, and it is still a net LOSS

| shape | before | with the attempt |
| --- | --- | --- |
| `-g` compile of the repro | **SIGSEGV (compiler)** | ok |
| runtime tuple crash | SIGSEGV | SIGSEGV (unchanged) |
| `str(Node(5).node)`, unannotated param | `5` | **`1`** |
| `str(self.node)` inside a method | `5` | **`1`** |
| `str(Node(5).node)`, ANNOTATED param | `5` | `5` |

So it fixes the compiler crash, does NOT fix the runtime crash, and turns a
correct value into a silent wrong one across a much broader shape than the crash
covers. Reverted rather than patched around, per CLAUDE.md. Verified against
`stable_linux_amd64/default/pinned` and `acf63b84d` that the `5` is the
pre-existing behaviour and the `1` was introduced by the attempt — the tree
carries none of it.

Why it goes wrong is the useful part, and the first explanation written here was
itself wrong — corrected after measuring rather than left standing.

**It is NOT that variant fields are broken.** Probed separately, `str()` of a
genuinely variant field is fine:

| shape | result |
| --- | --- |
| `def __init__(self, v)` + `self.v = v`, then `str(K(5).v)` | `5` ok |
| `self.v = None` in the ctor, `self.v = x` later, `str(k.v)` | `5` ok |
| the same, `print(k.v)` | `5` ok |

So forcing `tyVariant` is not wrong in itself. What the attempt produced was a
**mismatch**: the field was registered variant while another consumer still
resolved that name to the class, so two views disagreed about what the slot
holds. That is the same two-consumers problem as the crash, surfacing on the
value path instead of the crash path.

The lesson for whoever fixes this: changing the field's type in ONE place is what
breaks it. Every consumer of that name has to move together — which is also why
the crash survived the attempt unchanged.

### The runtime crash is a SECOND consumer, in a different place

Located, since `-g` compiles under the attempt: the fault is
`mov (%rax),%rax` inside **`pyvar_repr`** (`+352`, symbolised via the `.map`).
So the tuple ELEMENT carries an object tag over an integer payload — printing it
dereferences the value. The field's own typing is not the whole story, because
the attempt corrected that and the crash survived unchanged.

That means at least two sites consume this collision independently: the field
registration (`pyparser.inc:18126-18140`) and whatever types the tuple element
(`PyMakeTupleFrom`'s element path, ultimately `PyInferExprType`'s ident scan at
`pyparser.inc:3059`). A fix has to cover both, and the `str()` regression above
says the field half needs a real type rather than a variant.

## Gate

`make test-nilpy` + self-host byte-identical. Extend
`test/test_nilpy_local_named_like_a_class.npy` (it already pins the sibling bug)
with the field-path rows, including the `-g` compile as a row of its own so the
compiler crash cannot regress silently — **and** `str()` of an unannotated
field named like its class, which is the row the reverted attempt broke.

## 2026-08-04 (later) — FIXED at the root, not at the site

The reverted attempt failed because it guarded ONE consumer. The right lever was
one level down: **`FindUClass` matches case-INSENSITIVELY.**

That is correct for Pascal and wrong for Python, and it is what makes the whole
bug family reachable at all — a lowercase VALUE name finds a CapWords class,
which is the single most common naming convention in Python. `node` found
`Node`, `item` found `Item`, a parameter `b` found `class B`.

`PyIsClassTypeExact` (`pyparser.inc`) requires the class's stored name to match
the identifier exactly, and replaces `IsClassType` at the two sites where an
identifier stands in **value** position:

- `PyTypeFromTokenIndex`'s `tkIdent` case — which is what typed the FIELD from
  `self.a = a`;
- `PyInferExprType`'s ident scan (`:3059`) — the site the return-path fix
  deliberately did not reorder.

Genuine TYPE references keep the existing lookup, so nothing about declaring or
constructing a class changes.

### Measured after the fix

| row | before | after |
| --- | --- | --- |
| `class A` + `def __init__(self, a)` + tuple return | SIGSEGV | `(1, 2)` ok |
| the same under `-g` | compiler SIGSEGV | compiles, runs, correct |
| `class A(a, on_change=None)` + tuple of both fields | SIGSEGV | `(1, None)` ok |
| `str(Node(5).node)` — the row the reverted attempt broke | `5` | `5` ok |
| `str(self.node)` in a method | `5` | `5` ok |

Regression sweep, all matching CPython: a class used normally, a local holding an
instance, inheritance with an overridden method, `str`/`int`/`float`/`len`
builtins, `list(d.keys())`/`sorted`, an `Exception` subclass with `raise`/`except`,
a `@dataclass`, and a forward-referenced annotation `other: "Node"`.

Pinned by rows added to `test/test_nilpy_local_named_like_a_class.npy`, including
the `-g` compile as a row of its own so the compiler crash cannot regress
silently.

### What is deliberately NOT fixed

An **exact-case** collision — a local really called `Item` beside `class Item` —
is a genuine shadowing question rather than a spelling accident. The return path
handles it (`PyNameBoundInDef`, `e8b439e24`); the field path would need the same
treatment, and no repro of it crashing is known. Left alone rather than guessed
at.
