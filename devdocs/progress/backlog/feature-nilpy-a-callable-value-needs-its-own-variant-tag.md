---
track: A
prio: 70
type: feature
summary: "Give a callable value its own variant tag so `(3 + 4)(x)` can be refused. Track A, not N: the tag is defined in defs.inc and consumed by ir_codegen's clear/retain emitters, builtinheap and parser.inc. No decision needed — tag numbering is internal and renumberable."
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
