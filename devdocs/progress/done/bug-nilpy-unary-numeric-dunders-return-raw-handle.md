---
summary: "NilPy: abs(obj), ~obj and obj-as-index ignore __abs__/__invert__/__index__ — they return the raw instance HANDLE as a number, silently"
type: bug
track: N
prio: 55
status: done
owner: claude-AN
---

# `__abs__`/`__invert__`/`__index__` never dispatched — raw handle used as the value

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases).

## Measured (self-hosted binary at `3f2c5b915`)

```python
class C:
    def __init__(self, v): self.v = v
    def __abs__(self): return abs(self.v)
print(abs(C(-5)))
```
CPython: `5`. pxx: **`140450157559832`** — the instance pointer.

```python
class C:
    def __invert__(self): return "INVERTED"
print(~C())
```
CPython: `INVERTED`. pxx: **`123900459483161`.**

```python
class C:
    def __index__(self): return 2
print([10, 20, 30][C()])
```
CPython: `30`. pxx: **`IndexError: list index out of range`** — the handle was
used as the subscript.

## Cause

`__abs__`, `__invert__` and `__index__` appear **nowhere** in `compiler/**`
(`grep -oh '__[a-z_]*__' compiler/*.inc`), so nothing dispatches them and each
operand falls through to the numeric path with the instance handle standing in
for the value.

Note `__neg__` **is** dispatched (`compiler/parser.inc:8901`) — so unary minus
already has the branch these three need, and it is the natural place to model
the fix on. (That site raises a compile-time `Error()` when the dunder is
missing, which is its own defect —
[[bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising]].)

## Severity split

`__abs__` and `__invert__` are the silent ones: a plausible large integer, no
error, wrong wherever it flows. `__index__` at least raises here, but only by
luck — the handle happened to exceed the list length; for a short-lived small
handle it would silently index the wrong element.

## Fix shape

Mirror the landed ordering-dunder dispatch: dispatch when declared; when not
declared raise a genuine runtime `TypeError` via a pylib helper rather than
falling through to handle arithmetic. Apply the `PyRecIsPylibOwnClass` guard
(`compiler/symtab.inc`) so pylib's own rows keep their behaviour.

`__index__` additionally needs wiring at every integer-coercion site, not just
subscripts (slice bounds, `range()`, repeat counts) — worth scoping when picked
up, and a reason not to fold it silently into an `__abs__` fix.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython for each dunder declared and not declared (must raise a catchable
`TypeError`, never a handle-valued number).

## PARTIALLY FIXED 2026-08-01 — __abs__, __invert__ done; __index__ done for SUBSCRIPTS only

- `__invert__`: `PyParseBitOperand`'s `~` arm (`compiler/pyparser.inc`) now goes
  through `PyBitDunder`, the same helper the binary bitwise operators use — so
  it inherits the pylib exclusion and the runtime-`TypeError`-when-absent
  behaviour for free.
- `__abs__`: the `Abs`/`Sqr` builtin arm (`compiler/parser.inc`), dispatched
  ahead of the existing variant (`pyabs_v`) and numeric helper paths so those
  are untouched.

Both verified against CPython: `abs(Num(-5))` → `5` (was `140450157559832`),
`~Num()` → the method's result (was `123900459483161`).
`test/test_nilpy_dunder_unary.npy` is byte-identical to CPython and also covers
the no-dunder `~` raising a catchable TypeError, plus plain numeric `abs`/`~`
being unaffected.

Native confirm: self-host fixedpoint A==B==C from the pinned seed, testmgr
--tier quick GREEN; matrix offloaded to Track T.

### `__index__` — subscripts done, other coercion sites still open

`PyIndexCoerce` (`compiler/pyparser.inc`) asks a user class for `__index__` and
is applied at `PyMakeSuffixIndex`, the subscript site. `[10,20,30][Idx()]` now
returns `30` (was `IndexError` — and note it raised only by LUCK: the handle
happened to exceed the length, and a smaller one would have silently indexed the
wrong element).

**Still passing the raw handle**: slice bounds, `range()`, and sequence repeat
counts. `PyIndexCoerce` is the piece to reuse at each — it is a one-line call
per site — but each needs its own CPython-diffed case, so they are left for a
follow-up rather than wired blind. Ticket stays open for them.


## 2026-08-03 — slice bounds DONE; the rest measured shape by shape

`__index__` at slice bounds is fixed, in one place: `PyMakeSlice` coerces `lo`,
`hi` and `step` before choosing the pylib helper, so str, bytes, list and
variant receivers are all covered, extended slices included.

That was the SILENT half and the reason to do it first. A handle used as a
subscript is far past the end and raises IndexError; used as a slice bound the
same handle is CLAMPED, so `xs[C(1):C(3)]` quietly returned `[]` and
`"abcdef"[C(1):C(4)]` quietly returned `""`.

### The remaining sites, measured rather than listed

Each row is a one-line program against the same `C` declaring `__index__`:

| shape | pxx | CPython | kind |
| --- | --- | --- | --- |
| `[10, 20, 30][C(2)]` — LITERAL receiver | 30 | 30 | ok |
| `"abcdef"[C(2)]` — str receiver | c | c | ok |
| every slice form, all receivers | correct | correct | ok (this change) |
| **`xs[C(2)]` — NAMED list variable** | IndexError | 30 | loud, wrong |
| **`b[C(2)]` — named bytes variable** | IndexError | 3 | loud, wrong |
| **`[0] * C(3)`** | TypeError | [0, 0, 0] | loud, wrong |
| **`"ab" * C(2)`** | TypeError | abab | loud, wrong |

So "done for SUBSCRIPTS" was true only for a LITERAL or str receiver.
`PyMakeSuffixIndex` — which does call `PyIndexCoerce` — is reached from
`parser.inc:13433`, the suffix on a fresh construction. A subscript on a NAMED
container goes through the shared parser's class default-property dispatch
instead, which knows nothing about `__index__`.

**That is why the remaining half is not a one-liner:** the fix belongs in
`ParseClassRecordSelectors` / the ident suffix loop, which is shared Pascal
ground, so it needs a NilPy guard and Track A's gate rather than a NilPy-only
edit. The repeat counts (`*`) are a third, separate site.

`range(C(3))` could not be measured at all: `range` outside a `for` header is
not a callable in this frontend ("undefined variable (range)"), which is its
own gap.

### Verified

`test/test_nilpy_dunder_index_slice.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython: list, str and bytes slices with
object bounds, an extended slice with an object step, open-ended slices on
either side, the literal-receiver subscript as the already-working control, and
plain numeric slices as the regression control.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical, FPC seed clean.

## 2026-08-03 — the remaining `__index__` sites are DONE. Ticket closed.

Named-container subscripts and sequence repeat counts, the two rows the previous
session measured and left. Also `s[C(2)]` on a NAMED str, which the table above
recorded as "ok" — that was true only for a str LITERAL.

### Where each one went

- **named list / bytes subscript** — at the default-property dispatch in
  `parser.inc`, where the receiver class is in scope, NOT inside
  `ParsePropIndexArgs`. That distinction is the whole lesson of this change: see
  below.
- **named str subscript** — inside `PyMakeStrIndex`, which every str-subscript
  route funnels through.
- **repeat counts** — before the binop if-chain in `ParseBinOpAST`, and only
  when the coercion actually TURNS the pair into a repeat. `C(3) * 5` with no
  `__mul__` must stay a TypeError, not silently become 15.
- **`PyIndexCoerce` now forces its result to an integer.** `__index__`'s own
  inferred result is usually a variant (`return self.v` over an unannotated
  field), and a variant is not an ORDINAL — which is exactly what the repeat
  pair tests ask for, so `[0] * C(3)` fell past them into the arithmetic path.
  Python requires `__index__` to return an int, so the node now says so.

### The mistake worth recording: `ParsePropIndexArgs` was the wrong choke point

It looked like the ideal single site — five call sites, all subscripts, one
edit. It is also where a DICT subscript is parsed, and a dict key is the object
itself. Coercing there collapsed an object key onto its `__index__` value:

```python
d[K(1)] = "obj"
d[1]    = "int"
len(d)          # 2 on the pinned binary, 1 with the coercion in place
```

Caught by diffing against the PINNED binary rather than against CPython — the
CPython run failed for an unrelated reason in my probe, and the
pinned-vs-HEAD comparison is what actually answered "did I change this?".
`PyClassWantsIntIndex` now gates it: pylib's list and bytes only. A user class's
`__getitem__` argument is a key too, and stays untouched.

### Verified

`test/test_nilpy_dunder_index_sites.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython: literal and named receivers for
list/str/bytes, negative indices through the dunder, all four repeat orders
(`seq * obj` and `obj * seq`, list and str), a subscript STORE, plain integer
indices as the regression control, and the dict-key case as the guard against
the mistake above.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.

### Still open, deliberately, and filed as its own ticket

A missing `__index__` at a sequence subscript raises `IndexError`, where CPython
raises `TypeError`. Loud either way, so not silent — but the honest fix needs
the receiver's identity at a site that does not have it, exactly like the dict
hazard above. [[bug-nilpy-missing-index-dunder-raises-indexerror-not-typeerror]].
`range(C(3))` still cannot be measured at all: `range` outside a `for` header is
not a callable in this frontend, which is its own gap.

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
