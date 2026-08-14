---
track: N
prio: 60
type: bug
summary: "A parameter annotation NilPy cannot interpret (`type[X]`, `Sequence[X]`, `Iterable[X]`) is a hard ERROR, so the whole program is refused for a construct CPython does not enforce at all. Upward compatibility says an annotation it cannot read must degrade to Any, exactly as an ABSENT one already does — 29 of 168 neuzelaar files, the largest language gap once dotted imports landed."
status: working
owner: agent-AN
---

# An annotation NilPy cannot interpret refuses the whole program

- **Type:** bug (upward-compatibility violation) — **Track N**
  (`compiler/pyparser.inc`, the two parameter-annotation sites).
- **Found:** 2026-08-14, re-running the corpus census after
  [[feature-nilpy-dotted-imports-resolve-to-source-files]] landed and the
  language-gap column grew from 14 to 49 files, as that ticket predicted.

## The rule it breaks

CPython **does not enforce annotations at run time at all** — they are metadata.
So any program with an annotation is a program that "works on CPython", and
NilPy's upward-compatibility rule (`if code works on CPython, it must work on
NilPy`) makes refusing it a defect rather than a missing feature.

NilPy reads annotations statically as types, which is the whole point and is not
in question. What is wrong is the failure mode when the read comes back empty:

```
error: Nil Python: parameter message_type has an unsupported type annotation
```

The correct answer is already sitting two lines above it in the same routine —
an **unannotated** parameter defaults to `tyVariant` (Any). An annotation we
cannot interpret carries exactly as much type information as an absent one, so
it should land in the same place.

## The boundary, measured

Swept as `def f(x: ANN)` against HEAD, not inferred:

| annotation | today |
| --- | --- |
| `int` `str` `list` `Any` `Foo` `'Foo'` | OK |
| `List[int]` `Dict[str,int]` `Optional[int]` `set[str]` | OK |
| `list[int]` `dict[str,int]` `tuple[int,...]` `int\|None` | OK |
| `Callable[[int],None]` | OK |
| **`type[X]`** | **refused** |
| **`Sequence[X]`** | **refused** |
| **`Iterable[X]`** | **refused** |
| **`Callable[..., X]`** | **refused, and differently**: `error: unexpected token` |

Coverage is already broad — which is exactly why the tail should not be fatal.
The named gaps could each be added, and the next corpus would produce a new
three; the mechanism is the fix, not the names.

Note the last row is a **separate site**: `...` inside the annotation fails in
the annotation GRAMMAR, before anything returns `tyUnknown`, so the degrade
below does not cover it. Scope it explicitly.

## Why it is worth the priority

Census of the 168 git-tracked neuzelaar files against HEAD (recipe:
`devdocs/dev/python-libraries.md` §7): **29 files** fail on this one message,
under three different parameter names — the single largest language gap, and one
mechanism rather than 29.

## Proposal

At both parameter-annotation sites, `tyUnknown` degrades to `tyVariant` with a
WARNING naming the parameter, instead of `ErrorAt`. The warning is the part that
keeps this honest: the information is genuinely lost, and a misspelled forward
reference should still be visible — just not fatal. A `--strict-annotations`
flag can restore the refusal for anyone who wants it, per the standing
default-is-the-reference-implementation rule.

Degrading cannot produce a wrong VALUE: `tyVariant` is the dynamic path every
unannotated parameter already takes.
