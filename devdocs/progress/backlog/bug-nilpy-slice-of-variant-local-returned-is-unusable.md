---
track: N
prio: 75
type: bug
---

# Returning a SLICE of a variant local gives the caller an unusable value

```python
def mk(d, k):
    b = d.get(k, [])
    return b[:6]

d = {"C": ["a", "b"]}
print(len(mk(d, "C")))     # TypeError: expected a number, got object
```

CPython prints `2`. Returning the `.get()` result **without** the slice is fine:

```python
def mk(d, k):
    return d.get(k, [])    # len(mk(d, "C")) == 2, correct
```

So it is the slice of a **variant-typed local** that produces the bad value: the
result reaches the caller as something `len()` then coerces through
`pyvar_to_int` ("expected a number, got object") instead of a list.

## It is the INFERRED RETURN TYPE

Two probes pin it:

```python
def mk(d, k) -> list:      # annotated: WORKS
    b = d.get(k, [])
    return b[:6]
```

```python
b = d.get("C", [])         # inline, no function: WORKS
s = b[:6]
print(len(s))              # 2
```

So the slice value itself is right and `len()` on a variant holding a list is
right; what is wrong is the type NilPy infers for a body whose `return` is a
slice of a variant-typed local. The returned value then goes out through the
wrong coercion and reaches the caller as a bare object.

**FIXED** (2026-07-29): `PyInferExprType` now recognises a SLICE — a ':' at
bracket depth 1, via the new `PySliceBracketAt` — and types it as the receiver's
container kind (a str slice is a str; slicing a list or a variant holding one
yields a TPyList). Previously only the string INDEX form was handled, so
`return b[:6]` fell to the Integer default.

Verified against CPython on nine repros, including the app's exact shape
`d.get(k, [])[:6] if w else []` inside a def.

**NOT SUFFICIENT for songformatter** — a SECOND defect is in play, and a
top-down bisect of the real detector (a scratch copy at `/tmp/sfx`, rebuilt each
step) pins it to the METHOD, not the expression:

| `evidence=` in ViolationCountDetector.analyze | field reads back |
| --- | --- |
| `[]` | correct (0) |
| `penalty_evidence.get(winner.label, []) if winner else []` (no slice) | correct (0) |
| `penalty_evidence.get(winner.label, [])[:6] if winner else []` | **garbage** (1751084129) |
| `penalty_evidence.get("C", [])[:6] if winner else []` (literal key) | **garbage** |

So: the slice is the trigger, the key is irrelevant, and the SAME expression in
a small method is fine — every bottom-up repro matches CPython (annotated
`dict[str, list[str]]`, inside a method, Optional winner, a stored EMPTY list
under an existing key, keyword arguments with a trailing `debug=`).

Continuing the bisect INSIDE that method settles what it is — **the slice
result is an unowned temporary, i.e. a use-after-free**:

| in ViolationCountDetector.analyze | `len()` right after | field reads back |
| --- | --- | --- |
| `ev_local = []` then `evidence=ev_local` | 0 | **0, correct** |
| `ev_local = <the slice>` then `evidence=ev_local` | **0, correct** | **garbage** |

Same local, same field, same constructor — only the *provenance* of the value
differs. So the list `pylist_slice` hands back is correct when it is made and
still correct one line later, and is gone by the time the field is read: nobody
takes a reference to it. Dropping the neighbouring `debug=` kwarg changes
nothing, and the dict key is irrelevant.

That also explains why every small repro passes: the freed block simply is not
recycled before the read. In the real detector the 84-key nested loop churns the
heap in between, so the field comes back as ASCII bytes read as an integer.

### CONFIRMED: a VARIANT-held list stored into a class-typed field is not retained

Two more steps settle it. Neither the ternary nor the slice is the real
condition — what matters is that the value is a **variant** rather than a real
TPyList:

| in ViolationCountDetector.analyze | field reads back |
| --- | --- |
| `ev_local = <slice>` (no ternary at all), `evidence=ev_local` | garbage |
| `evidence=list(ev_local)` — same value, wrapped | **0, correct** |

`penalty_evidence.get(...)` yields a VARIANT (the dict-value type is not known
statically), so the slice of it is variant-held too. Storing that into a
`list[str]` field copies the payload without taking a reference; the variant
temp is then released and the field dangles. `list(x)` materialises a real
owned TPyList, so it survives — that is both the confirmation and the
application-side workaround.

### FIXED (2026-07-29, b9f7a82f9) — it was OWNERSHIP, not typing

`pyvarobj_owned` (pylib: `pyvarobj` + `PXXObjRetain`), plus an AST-level unbox
at the dataclass keyword-argument site in `PyClassCreate`, so the field owns
what it holds.

`IRLowerCallArg` (ir.inc ~2214) already unboxed a variant argument bound for a
class-typed parameter — but into a **bare** pointer. A class slot is never
released, so nothing balances that reference, while the variant TEMP the value
came out of IS released at the end of the statement and takes the object with
it. The field then pointed at a freed block. `list(x)` worked because it
materialises a separately-owned TPyList; `ev_local = []` worked because a real
TPyList local is never released either, so it simply leaked and survived.

**The premise recorded below is WRONG and is kept only as a record of what was
ruled out.** Instrumenting `PyClassCreate` directly shows slot 4 at
`ViolationCountDetector.analyze` is `tk=tyVariant` in BOTH the typing and the
emitting pass (`kind=67` = the ternary). Nothing is mis-tagged tyClass; the
"4 of 8 tyClass" count was over sites that legitimately pass a real list. That
is also why adding `PyUnboxVariantToClass` at the call site changed nothing —
it replaced ir.inc's unbox with an identical one. The retain is the whole fix.

Verified headless (no GUI needed): a `cp -r` of `~/songformatter` plus a
four-line driver calling `ViolationCountDetector().analyze(...)` directly and
printing `to_text(True)`.

### Earlier attempted fix, REVERTED — and what it ruled out (premise now known wrong)

Adding `PyUnboxVariantToClass` to the constructor keyword-argument path
(`PyClassCreate`'s re-emit loop) was tried and reverted: it changes nothing for
this bug and had no demonstrable benefit elsewhere, so it does not belong in
shared construction code on spec. What the instrumented compiler showed, which
narrows the search a lot:

- Of the 8 `DetectorResult(...)` sites in the EMITTING pass, 4 pass slot 4
  (`evidence`) as **tyVariant** and 4 as **tyClass**. `violation_count` is a
  class-tagged one — so at the constructor its argument is already typed
  tyClass while the value it carries at run time is a variant. **The mis-typing
  is upstream of the call**, which is why an unbox at the call site cannot help.
- The typing pass and the emitting pass DISAGREE on that argument (8 vs 4
  variant-tagged), which is itself worth chasing — a two-pass type disagreement
  is exactly the shape of the ABI mismatches recorded elsewhere in NilPy.
- `PyWiden(tyVariant, tyClass) = tyVariant`, so the ternary is not where the
  class tag comes from; `PyMakeSlice` correctly returns tyVariant for a variant
  base (`pyvar_slice`). Look instead at how the LOCAL / the argument re-acquires
  a tyClass tag on the second parse (PyNoteLocalType widening, or the field's
  declared type flowing back onto the expression).
- Incidental wart found on the way: the synthesised dataclass `create`
  parameter is class-TYPED but carries no record id (`ProcParamRecId` = 0); the
  class identity lives only in the field table (`UFldRec_`). Anything that needs
  the identity of a ctor parameter has to fall back to the field.

## Why it matters

This is the wall songformatter's key analysis dies on, and it is worth noting
how it presents there, because the visible symptom is nowhere near the cause:

```python
evidence=penalty_evidence.get(winner.label, [])[:6] if winner else []
```

The value is a correct (empty) list when it is passed — an instrumented copy of
the app prints `DBG slice n= 0` right before the constructor — and by the time
`DetectorResult.to_text` reads `self.evidence` back, `len()` answers
**1751084129** (ASCII bytes read as an integer) and the join walks off into a
segfault. Only that one detector of eight is affected; every other one builds
its evidence list inline.

## Repro / gate

The snippet at the top, matching CPython. Then songformatter's
`DetectorResult.to_text(verbose=True)` rendering all eight detectors — see
[[bug-nilpy-songformatter-first-render-walls]], whose remaining failure this is.

Instrumented copy still at `/tmp/sfx` (a `cp -r` of `~/songformatter` with
prints in `key_analysis.py`); rebuild it with
`pascal26 SongFormatter.py <out>` and run under `DISPLAY=:99`.
