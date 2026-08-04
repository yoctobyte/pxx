---
prio: 70
type: bug
track: N
summary: "SILENT MISCOMPILE: a parameter or local whose name matches a CLASS name is typed tyClass by return-type inference, so `def h(b): return b` beside `class B: pass` returns a raw pointer instead of the value. IsClassType is consulted BEFORE the locals table and the local can then never win. Ordinary Python; no diagnostic."
status: done
---

# A parameter or local named like a class is typed as that class

- **Type:** bug (silent miscompile, NilPy return-type inference) — **Track N**
- **Found:** 2026-08-04, Track A+N overnight, while establishing a baseline for
  [[bug-nilpy-non-constant-parameter-defaults-silently-become-none]]. It is not
  that ticket's bug; it was standing behind it and made its measurements lie.
- **SILENT.** No error at compile time or run time. The value comes back as a
  raw pointer printed as an integer.

## Minimal repro

```python
def h(b):
    return b
class B: pass
print(h([9]))
```

```
CPython:  [9]
pxx:      130841084690456
```

Ordinary Python. `class B` need not be used, instantiated, or related to `h` in
any way; it only needs to exist.

## Narrowing (measured, HEAD 2bc9c909b, self-hosted fixedpoint)

| repro | result |
| --- | --- |
| param `b`, class `B` | **corrupt** |
| param `b`, class `A` only | ok |
| param `z`, classes `A` + `B` | ok |
| param `b`, classes `A` + `C` | ok |
| param named exactly `Item`, `class Item` | **corrupt** |
| all-lowercase `class item` + param `item` | **corrupt** |
| LOCAL (not a param): `Box = v; return Box` beside `class Box` | **corrupt** |
| `def h(b) -> list` (return annotation) | ok |
| `def h(b: list)` (param annotation only) | **corrupt** |
| `def h(b): print(b)` — value not RETURNED | ok |
| `def h(b): return len(b)` | ok |
| `def g(): return []` — literal, no param | ok |

Affects `list`, `dict` and `str` values. An `int` survives, because the wrong
answer and the right one coincide in width.

**Warning for anyone re-measuring:** the obvious probe is `def h(b)` beside
`class A` / `class B`, which makes it look like "two classes corrupt, one does
not". That is a confound — the second class is named `B` and the parameter is
`b`. Vary the NAMES, not the count.

## Cause

`compiler/pyparser.inc:3059`, in `PyInferExprType`'s ident scan:

```pascal
if IsClassType(name) then tk := tyClass;
ci := PyFindConstraint(name);
if (tk = tyUnknown) and (ci >= 0) then tk := PyLocals[ci].TypeKind
else
begin
  si := PyProgSym(name);
  if si >= 0 then tk := Syms[si].TypeKind;
```

The class test runs FIRST and assigns `tk`. Every later chance to do better is
guarded on `tk = tyUnknown`, so once a class name matches, **the locals table is
never consulted** — the parameter that actually shadows the class cannot win.

`PyInferDefRetType` then sees `cur = tyClass` where it would otherwise have
taken the `if cur = tyUnknown then cur := tyVariant` path
(`pyparser.inc:16972`), registers the def as returning a class instance, and
the caller reads the handle as an object pointer. Measured via `PXXDBG=a.ir:h`:
the good build stores the parameter straight into `$pyresult` with `tk=22`
(tyVariant); the bad one inserts a call around it and stores `tk=6` (tyClass).

Two independent defects meet here, and fixing either alone leaves a live bug:

1. **Precedence.** A name bound as a parameter or local SHADOWS a class of the
   same name — that is plain Python scoping. The exact-case rows above
   (`class Item` + parameter `Item`) fail even with case-sensitive matching, so
   this is not a spelling problem.
2. **Case-insensitive lookup.** `IsClassType` (`symtab.inc:1187`) matches
   case-insensitively, Pascal-style, so `b` finds `B`. That is
   [[bug-nilpy-identifiers-are-case-insensitive]] (in `done/`) resurfacing in a
   path that ticket did not cover — and it is what widens this from "don't name
   a local after a class" to "don't name a local after any class in any
   casing", which no Python programmer would think to avoid.

## The hazard in fixing it

`PyInferExprType` runs in BOTH the shell pre-pass and the body pass, and the
file's own comments (`pyparser.inc:16843-16852`) record that the two passes
disagreeing is a **silent ABI mismatch** — the signature and the frame then
describe different types. `PyLocals` is populated in the body pass and empty in
the pre-pass, so simply reordering the locals lookup ahead of `IsClassType`
would make the passes answer differently for exactly these names.

So the fix must be **token-only**, the discipline the surrounding chases already
follow: decide "is this name bound as a parameter of the enclosing def, or
assigned anywhere in its body?" from the token stream, which both passes can
answer identically, and suppress the `IsClassType` branch when it is. The
parameter half is available from the def header the scan already walks past
(`PyInferDefRetType` skips it to find `bodyScanStart`); the assignment half is
the same `ident` + `tkAssign` scan `PyRetNameType` already does.

## Gate

`make test-nilpy` + self-host byte-identical. A `.npy` diffed against CPython
covering: a parameter named like a class (differing case AND exact case), a
local named like a class, the value returned vs merely used, and — as the
regression control that must NOT break — an actual `return SomeClass(...)`
construction and a genuine class-typed return, which are what the
`IsClassType` branch is there for.

## 2026-08-04 — FIXED for the RETURN path (e8b439e24); the FIELD path is split out

The repro in this ticket, and every row of its narrowing table, is fixed and
pinned by `test/test_nilpy_local_named_like_a_class.npy`.

Fixed in `PyInferDefRetType`, where the def's token range is known, NOT by
reordering the lookups in `PyInferExprType`. That routine runs in the shell
pre-pass (no `PyLocals`) and again in the body pass (`PyLocals` populated), and
the two answering differently is a silent ABI mismatch — the signature and the
frame then describe different types, which that file's comments record as having
already cost a crash. The new `PyNameBoundInDef` is token-only for the same
reason. Only the NAME-based conclusion is dropped, so the existing chase still
types `w = Word(); return w` as Word and a `return SomeClass(...)` construction
is untouched.

**Still open, as its own ticket:**
[[bug-nilpy-tuple-of-a-field-from-an-omitted-default-segfaults]] — the same
collision reaches a FIELD through `self.a = a`, and that route still crashes
(at run time, and in the compiler under `-g`). It is a different consumer: the
returned expression there is a tuple, not a bare ident, so this fix's guard
never applies. The obvious completion of the field half was attempted and
reverted — it trades the crash for a silent wrong value — and the measurements
are recorded there.


## Log
- 2026-08-04 — resolved, commit PENDING-COMMIT.
