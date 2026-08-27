---
track: N
prio: 58
type: bug
owner: frank1-AN
blocked-by: []
summary: "A nested def that captures a REBOUND parameter resolves the name to the parameter, not to the private slot the rebinding created — so `x /= 2` then a closure reading `x` fails with `invalid IR node reference in store_sym`, and rebinding to a str gives a runtime TypeError. Capturing a plain LOCAL of any type works, and capturing a rebound VARIANT parameter works, which is what localises it."
status: done
---

# A nested def capturing a rebound parameter uses the parameter's type

- **Type:** bug (Track N) — a compile fault on one shape, a wrong runtime type
  on another.
- **Found:** 2026-08-27 while resolving
  [[bug-n-augmented-true-division-does-not-widen-an-annotated-int-parameter]].
- **Measured:** at pinned **v383** (`18392d1d3181`) and at HEAD. **Pre-existing
  and unchanged** by the sibling fix — the messages differ at the two shas but
  both are wrong at both.

## Repro

```python
def o(x: int):
    x /= 2
    def inner():
        return x + 1
    return inner()
print(o(5))                     # CPython 3.5
```

```
v383: pascal26:5: error: invalid IR node reference in store_sym
HEAD: pascal26:5: error: invalid IR node reference in store_sym
```

...and the same shape rebinding to a string compiles and then fails at run time:

```python
def o(x: int):
    x = "s"
    def inner():
        return x + "t"
    return inner()
print(o(5))                     # CPython "st"
```

```
v383: TypeError: unsupported operand type(s) for +: 'int' and 'str'
HEAD: TypeError: expected a number, got str
```

## The boundary, which is what points at the cause

| shape | verdict |
| --- | --- |
| capture a plain **float** local | works — `2.5` |
| capture a plain **int** local | works — `3` |
| capture a plain **str** local | works — `st` |
| capture a rebound **variant** parameter | works — `2` |
| capture a rebound **typed** parameter | **broken**, both shapes above |

Capturing works for every ordinary local, and works for a rebound VARIANT
parameter — which is the one case that has had a private slot since
[[bug-nilpy-rebinding-a-list-parameter-aliases-the-callers-list]]. So the
capture scan handles a private slot fine; it does not find *this* one.

The likely difference is WHEN the slot is created. The variant slot is
allocated **before** `PyCollectLocalsAST`; the typed slot the sibling fix adds is
allocated **after** it (it needs the constraint table to know the type) and the
pass is then re-run. Moving the typed slot earlier — with a provisional type,
patched afterwards — would make the two identical and is the first thing to try.
Measure it; do not assume it.

## Gate

Both repros match CPython, plus the four control rows in the table above, plus a
`nonlocal` rebinding of a captured parameter.

## Resolution — the capture's TYPE was decided on the trial parse, like the by-ref flag beside it

The ticket's hypothesis was right about **when**, and the mechanism turned out
to be one step over from where it was looking: not the cells, but the nested
def's **proc registration**.

`PyQueueNestedDef` registers the nested def with a trailing capture parameter
per captured name, typed from `FindSym(cname)`. The enclosing body's local-typing
**trial parse** reaches that first — and at that moment a rebound TYPED
parameter's private slot does not exist yet, because it is allocated *after*
`PyCollectLocalsAST` (it needs the constraint table to know its type), while a
rebound VARIANT parameter's slot is allocated *before*. So:

- variant parameter → the trial already sees the variant local → capture
  parameter typed variant → works, and always did;
- typed parameter → the trial still sees the **Int64 parameter** → capture
  parameter typed Int64. The slot is then created and the pass re-run, but the
  proc **already exists**, so the re-run takes the `ALREADY REGISTERED` branch
  and nothing recomputes the signature. The call site passed the variant slot
  into an Int64 parameter.

That branch is already the home of exactly this correction — it re-applies the
by-ref decision there, with a comment saying it "was therefore taken without
them". The capture's TYPE has the identical problem and now sits beside it,
re-resolved by name:

```pascal
capSym := FindSym(PyCapName[procIdx * PY_MAX_CAPS + j]);
if (capSym >= 0) and (Syms[capSym].Kind in [skLocal, skParam]) and ... then
begin
  capNow := Syms[capSym].TypeKind;
  if TypeIsPromoInt(capNow) then capNow := tyVariant;
  ...
end;
```

The promo boxing mirrors the registration arm's own rule so the two spellings of
one decision cannot drift. The parameter's **symbol** is retyped with the
`TParam` — they are one declaration in two records, and leaving the symbol behind
is the silent-ABI-mismatch shape this file keeps meeting.

### The `nonlocal` row is why the re-apply is not restricted to by-value captures

The first cut skipped captures already marked by-ref, on the theory that a cell
carries a pointer and needs no retyping. Measured: the gate's `nonlocal` row
still failed, `TypeError: expected a number, got type` — **and it fails
identically on v387 pinned**, so it is pre-existing and in the same family
(the untyped-parameter spelling of it works, which is the same boundary again).
Dropping the guard fixes it and makes the rule simpler rather than more special:
by-ref-ness is carried by `IsRef`, not by the type, so there was never a reason
for the two to disagree about which type the capture has.

## Gate — met, plus three shapes it did not ask for

| row | pxx | CPython |
| --- | --- | --- |
| `o(5)` — capture a rebound typed param | `3.5` | `3.5` |
| `ostr(5)` — the same rebinding to a `str` | `st` | `st` |
| CONTROL — rebound UNTYPED param | `3.0` | `3.0` |
| CONTROL — a plain local | `3.5` | `3.5` |
| `nonlocal` write through the captured slot | `12.5` | `12.5` |
| the same shape inside a METHOD | `7.0` | `7.0` |
| captured by a LAMBDA | `104.5` | `104.5` |
| two rebound typed params of different types | `3.0z` | `3.0z` |

The four control rows of the ticket's boundary table all still hold. 24 named
closure / nested-def / lambda-capture canaries green (`nested_def_capture`,
`nested_def_default_capture`, `escaping_closure_many_captures`,
`nonlocal_escaping_closure`, `closure_lifetime`, `captured_class`,
`lambda_sibling_capture`, `lifted_lambda_return_value`, …). Self-host fixedpoint
verified, `converged after 1 round(s)`.

**Test:** `test/test_nilpy_nested_def_captures_a_rebound_parameter.npy`
(+`.expected`, registered) — the eight rows above.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
