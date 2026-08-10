---
track: N
prio: 50
type: bug
status: unfinished
owner: claude-AN
---

# `xs.sort(key=..., reverse=...)` fails with a bare "unexpected token"

- **Type:** bug (missing feature + poor diagnostic) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
xs = [3, 1, 2]
xs.sort(reverse=True)
```
```
error: unexpected token
  near:   xs  sort  >>> reverse
```

Same for `xs.sort(key=len)`. Meanwhile `sorted()` supports both:

| form | result |
| --- | --- |
| `sorted(xs, reverse=True)` | ok |
| `sorted(xs, key=len)` | ok |
| `sorted(xs, key=len, reverse=True)` | ok |
| `xs.sort()` | ok |
| **`xs.sort(reverse=True)`** | **parse error** |
| **`xs.sort(key=len)`** | **parse error** |

## Two things wrong

**1. The feature is missing.** `TPyList.sort`'s own comment says `key=`/
`reverse=` are not implemented because they need `PyCallKey1`'s callable
dispatch, which lives in `pyeval.pas` — and `pyeval uses pylib`, not the
reverse, so pylib cannot call it. That is a real constraint and honestly
documented.

But `sorted()` — which DOES live in `pyeval.pas` — already implements both,
including the insertion sort that moves a computed-key list in lockstep. So the
in-place method could delegate: sort into a new list with the existing code,
then copy back. `TPyList.reverse` (added 2026-08-02) is the same in-place
shape.

**2. The refusal is not loud, it is confusing.** The comment says these are
"refused loudly rather than guessed at", but what the user sees is a generic
`unexpected token` pointing at the keyword name — indistinguishable from a typo
in their own code. Compare the str-method table, which says exactly what is
wrong (`str method .find() takes one or two arguments`). Even without the
feature, this should name it.

## Gate

A `.npy` diffed against CPython covering `sort()` with `reverse`, with `key`,
with both, on an empty list and a single-element list, and confirming the sort
is IN PLACE (the original name observes the new order) with the return value
being `None` as Python's is.

## 2026-08-02 — `min()` / `max()` reject `key=` too

Same sweep, same family, different route — this one is a named diagnostic rather
than a parse error:

```python
words = ["bb", "a", "ccc"]
print(min(words, key=len))    # pascal26: error: Nil Python: min has no parameter named 'key'
print(max(words, key=len))    # same
```

`sorted(words, key=len)` and `sorted(..., reverse=True)` fail here as well, so
the `key=` callable is missing across the whole comparison family — `sort`,
`sorted`, `min`, `max` — not just the list method this ticket was filed for.
They should be gated together: whatever mechanism passes a callable into the
comparison is one piece of machinery serving all four.

`sorted(xs)`, `sorted(xs, reverse=...)` as the ONLY kwarg, `min(xs)` and
`max(xs)` without a key all work today.


## 2026-08-04 — re-measured (the ticket is now half stale), and BOTH halves are blocked, on different things

### What already works, which the table above no longer reflects

`sorted()` has gained the whole `key=`/`reverse=` surface since this was filed:

| form | today |
| --- | --- |
| `sorted(xs, reverse=True)` | ok |
| `sorted(xs, key=len)` | **ok** |
| `sorted(xs, key=len, reverse=True)` | **ok** |
| `xs.sort()` | ok |
| `xs.sort(reverse=True)` | still `Expected: ), but got: reverse` |
| `xs.sort(key=len)` | still a parse error |
| `min(xs, key=len)` / `max(xs, key=len)` | still refused |

So the "`key=` callable is missing across the whole comparison family" note is
out of date: `sorted` has it, and the machinery (`PyCallKey1`) is proven.

### `xs.sort(...)` — blocked on layering PLUS a frontend rewrite

`TPyList.sort` is a method of a class declared in `pylib.pas`, and `key=` needs
`PyCallKey1`, which is in `pyeval.pas` — `pyeval uses pylib`, not the reverse.
Neither unit has an `initialization` section, so the obvious dependency-inversion
hook (a `var PyKeyCall: function...` in pylib that pyeval fills in) has no
natural place to be assigned.

The workable shape is therefore a free function in `pyeval` that sorts in place
(sort into a new list with the existing code, copy the contents back — identity
is preserved, which is what `sort` being in-place means), plus a FRONTEND rewrite
of `X.sort(...)` to it. That rewrite is the cost: there is no list-method table
to add a row to (the str methods have one, lists do not), so it means a new
interception in the member-call path — and
[[project_nilpy_parsefactor_suffix_extension_point]] records that NilPy's postfix
handling has FOUR routes, so a hook added at one is a hook missing at three.

### `min`/`max` with `key=` — blocked on the keyword promoter's SAME-UNIT scoping

Implemented this one to the point of measurement, then reverted it. Moving the
list forms `min(l: TPyList)` / `max(l: TPyList)` out of `pylib` and into
`pyeval` with a `key: Pointer = nil` parameter (whole, not as a sibling, or
`min(xs)` becomes ambiguous across the two units) **works** — but only
positionally:

```python
print(min(words, len))        # 'a'   correct
print(max(words, len))        # 'bb'  correct
print(min(words, key=len))    # STILL refused
```

`key=` is not valid Python positionally, so that is inert for real code, and it
was reverted rather than left in the tree — the same call the shadowing ticket
made on 2026-08-03, for the same reason.

The blocker is precise. `PyPromoteProcOverloadByKwAt` (`pyparser.inc`) is what
lets a keyword name steer overload SELECTION, and its sibling search is
deliberately **scoped to the same unit** as the initially-chosen overload:

> Sibling search is scoped to the SAME UNIT as procIdx — that is what makes two
> Procs[] entries one Pascal overload SET in the first place, and it keeps this
> from promoting into an unrelated same-named routine from a different unit.

`min` is picked from `pylib` (the two-Variant scalar form) and the key-taking
list form is in `pyeval`, so the promotion refuses by design. The scoping is
right in general and wrong for this case: pylib and pyeval are not two unrelated
units, they are one language's builtins split for a layering reason.

**That also means [[bug-nilpy-keyword-arg-vs-overload-set]] is not finished**,
though it sits in `done/`. Its own body says the fix was not attempted; what
landed (`7be01f05f`) generalizes the promoter but keeps the same-unit scope.
Re-measured repro recorded there.

### Where this leaves the ticket

Both halves need something that is not in this ticket:

- `sort` → a `pyeval` in-place sort plus one frontend rewrite, done across all
  four postfix routes;
- `min`/`max` → the keyword promoter allowing pylib↔pyeval as one overload set
  (or those two builtins living in one unit).

Moved to `unfinished/`. The diagnostic complaint in the original report —
`unexpected token` pointing at the keyword name, indistinguishable from a typo —
is still true and is the cheapest independent improvement available here.

### 2026-08-04 (later) — the `min`/`max` half is DONE

[[bug-nilpy-keyword-arg-vs-overload-set]] was the blocker and is fixed: the
keyword promoter now falls back across units, so `min(xs, key=len)` and
`max(xs, key=len)` resolve to the pyeval list forms and match CPython
(`4970562a5`). The implementation reverted earlier today was re-applied on top
of it rather than rewritten.

**Only `xs.sort(key=, reverse=)` remains on this ticket**, blocked on what the
2026-08-04 note describes: a pyeval in-place sort plus a frontend rewrite of the
method call, done across all four NilPy postfix routes. Nothing about that
changed.

## 2026-08-04 (overnight) — `reverse=` is DONE, and it needed NO frontend work at all

The remaining half was being sized as one indivisible job ("a pyeval in-place
sort plus a frontend rewrite across all four postfix routes"). It splits, and
the two halves have nothing in common:

- **`reverse=` needs no callable**, so the pylib/pyeval layering that blocks
  `key=` does not apply to it. It is the opposite `pyvar_gt` comparison, and
  `pyvar_gt` is already in pylib (`max()`/`min()` use it).
- **`key=` alone** is what needs PyCallKey1, hence the pyeval free function and
  the frontend rewrite.

### The parse error was never about keyword arguments

Measured cause, and it reframes complaint 2 of this ticket. The method-call path
in `parser.inc:6117` drives its argument loop off the callee's arity:

```pascal
while mai <= Procs[mpi].ParamCount-1 do
```

`TPyList.sort` declared no parameters, so `ParamCount-1 = 0`, the loop body
never ran, and the keyword recognizer (`PyKwArgIndex`) that lives *inside* that
loop never looked at `reverse` at all. Control fell straight to
`Expect(tkRParen, ')')`. So the method form was not "rejecting keyword
arguments" — it was rejecting arguments of any kind, and a missing FEATURE
surfaced as a bare token error pointing at the keyword name.

That is why **declaring the parameter is the entire fix**: with `ParamCount = 2`
the loop runs once, `PyKwArgIndex` binds `reverse`, and the existing
`PyBindKwArgs` orders it. No parser edit, and no rewrite across the postfix
routes — the other two routes (`PyParseClassMethodCall`,
`PyParseVariantMethod`) already fill trailing defaulted parameters via
`ProcParamHasDefault` -> `DefaultArgValueNode`, so a plain `xs.sort()` keeps
working through all of them. Verified on a variant receiver, a subscript
receiver and a for-in variable.

### Complaint 2 falls out for free

`xs.sort(key=len)` now reports

```
Nil Python: TPyList.sort has no parameter named 'key'
```

instead of `unexpected token`. The named diagnostic the ticket asked for is a
consequence of the callee having parameters at all, not something that had to be
added.

### Stability

`reverse=True` is not "sort ascending, then reverse" — CPython's sort is stable
in both directions, so equal elements keep their input order either way.
Flipping which operand `pyvar_gt` receives keeps the comparison STRICT, so equal
elements still do not swap. Pinned by the duplicate rows in the test.

### Verified

`test/test_nilpy_list_sort_method.npy` EXTENDED rather than a new file (it
existed, and its header comment claiming "No key=/reverse= yet" was itself now
false), converted to a `.expected` + `diff` wiring: both directions, the
degenerate empty/single lengths, duplicates both ways, `reverse=False` equalling
a plain sort, the `None` return, in-place mutation through a second binding, and
the variant / for-in receiver routes. 14 rows byte-identical to CPython.

`compiler/builtin/pylib.pas` is frozen into `stable_linux_amd64` but the
compiler does not `use` pylib — only NilPy programs do — so this needs no
re-pin for the self-host fixedpoint
([[project_builtin_change_needs_repin_for_gate_fixedpoint]]). A `make pin` is
still what makes it reach Track B's stable binary.

### What is left, and the ticket stays open for it

`xs.sort(key=...)` only. Its blocker is unchanged and real: `PyCallKey1`,
`pyclosure_is` and `pyboundfn_is` are all in `pyeval.pas`, `pyeval uses pylib`
and not the reverse, and no builtin unit has an `initialization` section to hang
a hook var on. The shape stays as described above — a pyeval free function that
sorts into a new list and copies back, plus a frontend rewrite — with one
addition found while measuring this half: the Variant->Pointer coercion for a
callable argument (`pyvar_callable_ptr`) exists ONLY in the free-call branch of
`ParseFactorCore` (`parser.inc:13280`), so merely adding `key: Pointer` to the
pylib method would hand the variant's TAG word to the callee as a code address.
The rewrite to a free call gets that coercion for free, which is now a second
independent reason to prefer it.

Also filed from this work: [[decide-nilpy-builtin-keyword-only-parameters]] —
`xs.sort(True)` is accepted positionally (measured), where CPython's
`sort(*, key=None, reverse=False)` refuses it. Laxness, not a wrong answer, and
the same latency already exists for `sorted`/`min`/`max`; parked on Track U
rather than guessed at.

## Re-measured 2026-08-10 at HEAD (b17cf2621) — the title is now wrong on two counts

| shape | measured at HEAD |
| --- | --- |
| `xs.sort(reverse=True)` | **works** — `[3,2,1]`, matches CPython |
| `sorted(ys, key=len)` | **works** |
| `sorted(xs, reverse=True)` | **works** |
| `ys.sort(key=len)` | **the only gap** |

And it is no longer a *bare parse error*. The diagnostic is now named and
accurate:

```
error: Nil Python: TPyList.sort has no parameter named 'key'
```

So: `reverse` is done, the error message is fine, and `sorted(key=)` already
works — meaning the **key machinery exists and simply is not wired to the
in-place `sort` method**. That is a much smaller job than this ticket describes
and a strong starting lead.

**Duplicate:** [[bug-nilpy-list-sort-method-missing]] (backlog, prio 50) covers
exactly this residue — `list.sort(key=...)`, with `sorted()` noted as working.
Its own text is also stale (it reports `TPyList has no method sort`; the method
now exists and takes `reverse`). These two should be merged into one ticket
rather than both surviving; the backlog one is the copy that is actually visible
to the ranker.
