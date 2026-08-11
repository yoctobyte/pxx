---
track: A
prio: 70
type: feature
summary: "Give a callable value its own variant tag so `(3 + 4)(x)` can be refused. Track A, not N: the tag is defined in defs.inc and consumed by ir_codegen's clear/retain emitters, builtinheap and parser.inc. No decision needed — tag numbering is internal and renumberable."
status: done
owner: claude-an-1
---

> **Re-tracked N -> A on 2026-08-11.** Filed as Track N because the *motivation*
> is NilPy; the CODE is Track A's — `defs.inc` defines the tag, and
> `ir_codegen.inc`'s variant clear/retain emitters, `builtinheap.pas` and
> `parser.inc` consume it. That is the shared-internals case CLAUDE.md says a
> frontend hands to A rather than edits.
>
> It was also briefly blocked on a Track U decision about the tag space being a
> permanent public commitment. **That was withdrawn** — see
> `rejected/decide-variant-tag-space-is-a-language-wide-commitment`. We never
> intended FPC binary compatibility (`variants.pas` says so outright, and the
> numbers never matched), and no tag reaches a durable format, so a bad number
> costs a refactor across the ~7 files mentioning `VT_`. Pick a sensible number
> and move; no sign-off required.

# A callable value needs its own variant tag

Splits out the part of `bug-nilpy-calling-a-non-callable-segfaults` that the
guard landed there could not close, with the measurement that proves it.

## The residual hole

`PyNotCallable` now refuses every tag that nothing callable ever wears — 1
(VT_INT), 3, 4, 5, 6, the promotable-int block, and 7 without a `__call__`.
**Tag 2 (VT_INT64) is left permitted**, and that is a real hole:

```python
def get(w):
    if w == 1: return 3 + 4
    return "x"
get(1)(3)          # still SEGFAULTS
```

`5` boxes as VT_INT (1) and is caught. `3 + 4`, `2**40` and `int("99")` box as
VT_INT64 (2) — the **same tag a plain compiled def's code address rides as**.
1-vs-2 is an integer WIDTH distinction; it carries no information about whether
the payload is code. Refusing tag 2 would break every ordinary call through a
def value.

## The measurement, so this is not re-derived

Probing every callee that reaches the guard across the whole `.npy` corpus:

| tag | samples | what it is |
| --- | --- | --- |
| 10 | 245 | lifted bound-fn |
| 2 | 106 | **plain def code address** |
| 9 | 12 | pyeval closure |
| 0 | 2 | None (already raised) |

Tags 1/3/4/5/6/7 appeared **zero** times — which is what made refusing them
safe. Tag 2's 106 samples are what make refusing it impossible.

## The fix

Give a callable value its own tag (12), stamped wherever a def's code address
is boxed as a variant, so the guard becomes an allow-list on {8,9,10,11,12}
and the int case closes with everything else. Same shape as VT_CLASSREF (11),
which was added for exactly this reason — an untagged RTTI blob address was
indistinguishable from a code address, and `cls(3)` jumped into the blob.

This is the third representation-collision in
`project_nilpy_callable_has_three_representations`; the tag is what ends the
family rather than adding a fourth guard.

## Gate

`make test-nilpy` + self-host byte-identical. The existing
`test_nilpy_calling_a_non_callable.npy` documents the uncovered case in a
comment — when this lands, move `3 + 4` into the test body and delete the note.

---

## Resolution

`VT_CALLABLE_TAG = 12` (defs.inc). Stamped in the backends' variant-boxing tag
selection off **the source IR node**, not its type kind — `IRSrcIsCallable` in
ir.inc, applied at all five boxing sites (x86-64 `IR_VAR_STORE` + `IR_VAR_BOX`,
i386's two, aarch64's two). The type kind is precisely what cannot tell a code
address from an integer, which is why the discrimination had to move.

`PyNotCallable` is now an **allow-list** — {8, 9, 10, 11, 12, and 7 with a
`__call__`} — so VT_INT64 closes with everything else, along with
VT_EMPTY-with-a-payload and any tag added later that forgets to say whether it
is code. The old refusal consts in pyeval are gone with it: an unclassified tag
is refused by default rather than let through.

### What the measurement changed about the fix

The ticket's plan said "stamp wherever a def's code address is boxed". Probing
the corpus showed **two** shapes wearing tag 2, not one:

| shape | example | first plan | actual |
| --- | --- | --- | --- |
| `IR_PROCADDR` | `{"a": add}[k](1, 2)` | covered | covered |
| a callable CONSTRUCTOR call | `apply2(lambda a, b: a - b, 6, 7)` | **missed** | covered |

The second is a heap callable (`pyboundfn_*` / `pyclosure_*`) boxed in an
ARGUMENT position, where `PyBoxCallableValue` deliberately does not run. Shipping
the allow-list without it turned five green tests red — `callable_param_heap_
callable`, `closure_lifetime`, `callable_field_all_shapes`, `escaping_closure_
many_captures`, `block_nested_rebind_widens` — every one an `Unhandled
exception: TypeError: object is not callable` on working code. **The allow-list
is what surfaced them**; a refusal list would have shipped the same gap silently.

It does NOT take the owning tags 9/10: the slot never retained the object, so
claiming an owning tag would release something it does not own. VT_CALLABLE
means "the payload is callable and the slot does not own it" — exactly the
lifetime these values already had as VT_INT64. The retagging changes what the
guard can SEE and nothing about who frees what, which is what makes it safe.
Dispatch is unaffected either way: `PyCallableObj` keys on the object's magic.

### Fallout the tag fixed on its own

A def wore VT_INT64, so it *was* an int to everything that asked:
`type(add).__name__` answered `'int'`, `isinstance(add, int)` answered True, and
`print(add)` printed the entry point as a decimal. All three now answer
CPython's way (`'function'`, False, `<function at 0x...>`). `PyVarTypeName` also
gained 8/9/10/11, which had been falling through to `<unknown>`.

Three rendering paths carried their own copy of the callable-tag list
(`pystr_of`, `pyvar_repr`, `pyvar_print_of`); they now share `PyVarIsCallableTag`,
so the next tag cannot be right in `print()` and wrong in an f-string.

`pyvar_to_int` accepts tag 12 in its payload arm — internals read a callable
variant back as a machine word, and that reading is what the VT_INT64 collision
was accidentally providing. VT_CLASSREF (11) deliberately stays out: it has
always had its own tag and has always raised.

### Verification

- `test_nilpy_calling_a_non_callable` extended with the three tag-2 shapes
  (`3 + 4`, `2 ** 40`, `int("99")`) plus a def reached through two nested dicts.
  **Segfaults on `pinned`**, passes here, and byte-identical to CPython's own
  output for the whole file.
- The 9 corpus files that produced tag 2 before the change all produce output
  **identical to `pinned`** after it.
- `tools/gate.sh quick` GREEN; self-host fixedpoint (byte-identical);
  `make test-nilpy` green.

### Filed on the way

`bug-nilpy-a-parenthesised-callee-drops-its-arguments` — `x = (add)(4, 5)`
answers a raw code address instead of 9, because on an assignment RHS the parser
DISCARDS the argument list. Found trying to put the ticket's own `(3 + 4)(x)`
spelling into the test: that form never reaches this guard at all, so no tag
could have fixed it. The `get(1)(3)` spelling in the ticket body is the one this
closes.

### Not a permanent commitment, confirmed again

Nothing serializes a tag; `variants.pas` disclaims FPC's model. Renumbering 12
would cost a grep over the files mentioning `VT_`. The tag is deliberately kept
below `VT_PROMO_BASE` so the emitters' `jl done` range test skips it for free.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
