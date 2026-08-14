---
track: N
prio: 55
type: bug
summary: "`MessageT = TypeVar(\"MessageT\")` at module scope dies with `undefined variable (TypeVar)`: `typing` is a consumed-and-ignored import, so the names it exports that have a RUN-TIME call form — TypeVar, Generic, NewType, cast — are bound to nothing. The largest remaining language gap in the neuzelaar census once unreadable annotations stopped refusing modules."
status: done
owner: agent-AN
---

# `TypeVar(...)` is an undefined variable

- **Type:** bug (upward-compatibility violation) — **Track N**.
- **Found:** 2026-08-14, in the census re-run after
  [[bug-n-an-uninterpretable-annotation-refuses-the-program]] landed and the
  files that used to die at an annotation reached their `TypeVar` line instead.

## Reproduce

```python
from typing import TypeVar
MessageT = TypeVar("MessageT")
print("ok")
```

```
error: undefined variable (TypeVar)
```

## Why

`typing` is on `PyImportRootIsConsumedOnly` — the from-import is consumed and
dropped, on the reasoning that what it exports is "a compile-time annotation with
no run-time existence, or an ordinary pylib symbol already in scope". That is
true of `List`, `Optional`, `Dict` and friends, which only ever appear inside
annotations and are read by `PyAnnTypeAt`, never evaluated.

It is **not** true of the handful of typing names that are CALLED at run time:
`TypeVar`, `NewType`, `Generic`, `cast`, `overload`. Those appear in ordinary
statement position, so consuming the import leaves the name unbound and the
program fails at the call, naming `TypeVar` rather than the import that dropped
it — the exact "silently dropping an import is the worst shape a gap can take"
failure the consumed-only list's own note warns about, arrived at from the other
direction.

## What the answer probably is

NilPy erases generics, and after
[[bug-n-an-uninterpretable-annotation-refuses-the-program]] the resulting name is
only ever *used* in annotations, which now degrade to Any. So the value a
`TypeVar` call produces never has to be anything in particular — binding it to a
harmless object (its own name string, say) makes every observed use work.

`cast(T, x)` is the one that carries real semantics and they are trivial:
CPython's `cast` returns its second argument unchanged.

Scope `Generic[...]` as a base class explicitly — `class Bus(Generic[MessageT])`
is a different site (a base-class list, not a call) and should not be assumed to
fall out.

## Measured

21 of 168 git-tracked neuzelaar files fail with `undefined variable`, the largest
remaining language gap; `TypeVar` is the leading single cause. Recipe:
`devdocs/dev/python-libraries.md` §7 — regenerate rather than trusting this
number.

## Resolution

Four of the five typing names that have a run-time form now work; the fifth
(`@overload`) is split out as [[bug-n-overload-decorator-is-refused]] because its
answer is a different mechanism — see below.

| name | answer | where |
| --- | --- | --- |
| `TypeVar` | pylib routine returning CPython's own `~T` spelling — the result is opaque, nothing inspects it | landed earlier in this ticket |
| `NewType` | evaluates to the SUPERTYPE itself; the name argument is metadata and is dropped | landed earlier in this ticket |
| `cast` | evaluates to the SECOND argument, unchanged | this pass |
| `Generic` / `Protocol` in a base list | ERASED, exactly as `object` already is | this pass |
| `@overload` | skipping a definition, not producing a value | [[bug-n-overload-decorator-is-refused]] |

### `cast` — the type is skipped as TOKENS, not parsed

CPython's `cast(T, x)` returns `x` having done nothing with `T`, so the value is
just the expression. The first argument is **stepped over as balanced tokens**
rather than handed to the expression parser, because it is written in annotation
language: `cast(List[int], x)` and `cast("Node", x)` are ordinary, and `List` is
itself one of the names the consumed-only import drops — parsing it would
reintroduce the very `undefined variable` the arm exists to remove.

Guarded by `PyUserNameShadowsHere('cast')`, so a module with its own `def cast`
gets its own. `cast` is a common enough word that hijacking it would trade one
upward-compatibility break for another; the intercept only fires where the
alternative was `undefined variable (cast)`.

### `Generic[T]` forced the base list to become a LIST

The header parsed exactly ONE base and then hard-errored on the comma. So
erasing `Generic` in first position was not enough: `class Bus(Service,
Generic[T])` — the spelling typed code actually uses — still died on the
multiple-inheritance refusal, for a class that names exactly one real parent.

The base parse is now a loop that counts REAL bases; erasable entries
(`object`, `Generic[...]`, `Protocol[...]`) do not count. So the refusal fires on
`class C(A, B)` as before and does not fire on a header that only looks like
multiple inheritance. Both orders work (`(Service, Generic[T])` and
`(Generic[T], Service)`), as does `class E(Exception, Generic[T])`.

A user class named `Generic` or `Protocol` WINS — these are erased because there
is nothing to point at, so if there is, point at it.

### Verified against the CPython oracle

`test/test_nilpy_typevar_and_newtype.npy` extended (cast in three shapes,
Generic in both orders, Protocol, Exception+Generic) — **output byte-identical
to CPython**, and it is the expected file. New
`test/test_nilpy_cast_user_shadow.npy` pins the shadowing direction, also
CPython-identical. The multiple-inheritance refusal is unchanged and still
fires with its full message.

One deliberate divergence recorded in
`devdocs/dev/nilpy-semantics-divergences.md`: instantiating a `Protocol`
directly succeeds here and is a `TypeError` in CPython. Not a bug under the
upward-compatibility rule — a program CPython accepts and runs never does it.

### Not re-measured

The neuzelaar census could not be re-run: the corpus is not on this box. The
21-of-168 `undefined variable` figure in the ticket above is therefore still the
2026-08-14 number — regenerate with `devdocs/dev/python-libraries.md` §7 rather
than trusting it.

### Landmine hit

`PyUserNameShadowsHere` is defined ~3300 lines BELOW the new call site. pxx
accepts that; FPC does not, and the seed canary caught it
(`Identifier not found`). Fixed with a forward declaration — the same shape as
`bug-a-fpc-seed-drift-emitasmx64-forward`.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary). `compiler/builtin/**` untouched, so no re-pin.

## Log
- 2026-08-14 — resolved, commit b1128981e.
