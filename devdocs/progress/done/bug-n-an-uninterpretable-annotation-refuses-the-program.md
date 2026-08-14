---
track: N
prio: 60
type: bug
summary: "A parameter annotation NilPy cannot interpret (`type[X]`, `Sequence[X]`, `Iterable[X]`) is a hard ERROR, so the whole program is refused for a construct CPython does not enforce at all. Upward compatibility says an annotation it cannot read must degrade to Any, exactly as an ABSENT one already does — 29 of 168 neuzelaar files, the largest language gap once dotted imports landed."
status: done
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

## Resolution (2026-08-14)

Shipped. **Seven** sites, not the two the ticket named — each was reached by a
different position in the grammar, each failed differently, and three of them did
not fail at the annotation at all:

| position | how it failed before |
| --- | --- |
| parameter | `unsupported type annotation` |
| `def` return type | `expected type annotation` |
| **method return type** | **COMPILED, then `TypeError` at RUN time**: the member pre-pass maps `tyUnknown` to Integer, so returning a list from `-> Sequence[int]` hit "expected a number, got object" |
| dataclass field | `unsupported dataclass field type for xs` |
| `self.x` in `__init__` | `cannot infer the type of field self.xs - annotate it` — about a field that IS annotated |
| **module-level variable** | **matched no arm at all**, so the name was never bound: `undefined variable (v)` at the first USE |
| `Callable[[X], R]`'s own parameter | `unsupported Callable parameter type` |

The last one is the clearest statement of what the whole class of bug was: its
result is **discarded** two lines later — every Callable parameter registers as
`tyVariant`, because both ends of a function value pass variants — so the error
gatekept a value nothing reads, and refused the module for it.

**The enabling change was underneath all of them.** `PyAnnTypeTermAt` now
CONSUMES a term it does not know (name plus balanced subscript) and still
answers `tyUnknown`. Without that no degrade was possible: leaving `[X]` in the
stream turned "unsupported annotation" into `unexpected token` one line later,
pointing at nothing. This is the same call the `tuple` branch already made and
carries a note about, generalised. `Callable[..., R]` folds in there too — there
is no arity to register, and registering 0 would be an ABI lie the first call
with an argument pays for.

Degrading is **warned, not silent**: the type information really is lost and a
misspelled forward reference should stay visible. A `--strict-annotations` flag
can restore the refusal if anyone wants it.

## Measured

Census (`devdocs/dev/python-libraries.md` §7), 168 git-tracked neuzelaar files,
three runs across this session:

| | after dotted imports | after this fix |
| --- | --- | --- |
| language gaps | 49 | 48 |
| `unsupported type annotation` | **29** | **0** |
| `unsupported dataclass field type` | **10** | **0** |
| `unsupported Callable parameter type` | **11** | **0** |
| compiling | 18 | 19 |

**Read that carefully rather than as a disappointment.** Three buckets totalling
50 file-failures went to zero and the compiling count moved by one, because a
file has many blockers and clearing one moves it to the next: `undefined
variable` went 10 -> 21 as the files that used to die at an annotation reached
their `TypeVar(...)` call instead. That is the same lower-bound effect
[[feature-nilpy-dotted-imports-resolve-to-source-files]] measured, and it is why
this campaign is scheduled by MECHANISM and not by compiling percentage.

What the corpus asks for next, regenerated: `undefined variable` at 21 (the
largest single cause is `TypeVar` — see
[[bug-n-typevar-call-is-an-undefined-variable]]), `@dataclass frozen=True` at 10,
`super().__new__` at 10.

**Gate:** `test/test_nilpy_unreadable_annotation_is_any.npy` (+ `.expected` from
CPython), covering all seven positions and pinning that a READABLE annotation is
still read; wired into `test-nilpy`.

## Log
- 2026-08-14 — resolved, commit 17faabc3e.
