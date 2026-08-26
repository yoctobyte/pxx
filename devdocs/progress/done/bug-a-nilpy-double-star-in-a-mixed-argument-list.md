---
track: A
prio: 58
type: bug
blocked-by: []
summary: "After a057789bc, `f(**d)` works but every MIXED form still fails: `f(3, **d)` (expected expression), `f(**d, b=7)` and `f(**d, **e)` (unexpected token). `f(3, **d)` never reaches the star-forwarding branch at all — that branch is guarded on tkStar at the START of the argument list — so this is the ordinary argument loop's gap, not an extension of the previous fix."
status: done
owner: opus5-frank1
---

# `**` anywhere but first in an argument list

- **Type:** bug (parser) — **Track A** (`compiler/parser.inc`, shared A/P).
- **Filed by:** frank2 on Track N, 2026-08-17, verifying the handoff
  [[bug-a-nilpy-leading-double-star-in-a-call-is-not-detected]] (fixed,
  `a057789bc`). Track N may not edit `parser.inc`; filed and handed off.

## Measured at HEAD (a057789bc, self-host converged)

```python
def f(a=1, b=2): return a + b * 10
d = {"a": 5}
e = {"b": 7}
```

| shape | pxx | CPython |
| --- | --- | --- |
| `f(**d)` | **65** ✅ | 65 |
| `f(3, **d)` | `error: expected expression` | 63 |
| `f(**d, b=7)` | `error: unexpected token` | 75 |
| `f(**d, **e)` | `error: unexpected token` | 75 |

Not regressions — none of these worked before either. They are what the
scoped-to-five-lines fix deliberately did not reach.

## Why this is not "finish the previous fix"

`f(3, **d)` **never enters the star-forwarding branch.** That branch
(`parser.inc:15874`) is guarded on `CurTok.Kind = tkStar` at the **start** of
the argument list; with a leading `3` the parser takes the ordinary argument
loop, which has no `**` element handling at all. So the work is in that loop —
recognising a `**` element mid-list and routing the call to the forwarding
lowering — not in extending the branch's look-ahead.

`f(**d, b=7)` and `f(**d, **e)` do enter the branch, but its trailing handling
accepts exactly one `*`/`**` follower and nothing else.

Worth stating because the originating ticket
[[bug-nilpy-a-dict-cannot-be-unpacked-into-a-call]] predicted the opposite —
*"Mixed `f(x, **d)` and `f(**d, y=1)` fall out of the same lowering"*. Measured,
they do not.

## Shape of the fix (a suggestion, not a design)

The runtime is still not the problem: `PyStarForwardCall` binds a dict onto
named slots correctly, and explicit arguments winning their slots is a
compile-time matter. The likely shape is to collect the argument list
generically — positional items, `*` items, `**` items, keyword items — and hand
the whole thing to the existing forwarding lowering when any star element is
present, rather than having two separate paths that each know about only some
element kinds. That is the `normalise-dont-special-case.md` move; bolting a
`**` case onto the ordinary loop while the branch keeps its own parser is how
this stays broken in a fourth shape.

Sizing honestly: this is bigger than five lines and touches the main argument
loop, so it wants its own gate run rather than riding along with something else.

## Gate

`make compiler/pascal26` + a `.npy` diffed against CPython covering the four
rows above plus `f(x, y, **d)`, `C(**d)` on an ordinary `__init__`, and the
existing `f(**d)` / `f(*lst)` / `dict(**d)` staying green, then
`tools/gate.sh quick`.

**Do not skip the FPC seed canary.** `a057789bc` added a cross-include call and
PXX tolerated a duplicate forward that FPC — single-pass — rejects; the canary
was the only thing that caught it. Any change here that calls a `pyparser.inc`
helper from `parser.inc` has the same exposure.

## Outcome

Fixed. Every shape in the ticket's table now agrees with CPython, along with
seven more that were never measured.

### First: the ticket's oracle column is wrong on two rows

Measured against CPython 3 before touching anything:

| shape | ticket claims | CPython actually |
| --- | --- | --- |
| `f(**d)` | 65 | **25** |
| `f(3, **d)` | 63 | **TypeError: got multiple values for argument 'a'** |
| `f(**d, b=7)` | 75 | 75 ✅ |
| `f(**d, **e)` | 75 | 75 ✅ |

With `d = {"a": 5}` and `f(a=1, b=2) -> a + b*10`, `f(**d)` is `5 + 2*10 = 25`;
pxx already answered 25. And `f(3, **d)` binds `a` twice, so there is no value
to expect. The 65 is real, but it belongs to the SIBLING ticket
[[bug-a-nilpy-leading-double-star-in-a-call-is-not-detected]], whose repro
declares `d = {"a": 5, "b": 6}` — the row was carried across and the `d` was
not. The numbers were reasoned, not run
(`devdocs/dev/debugging-playbook.md`). The row that *does* exercise "a mapping
after a positional" is `f(3, **e)` — 73 — and that is what got fixed.

### The measurement that pointed at the shape

`f(*lst, **e)` **already worked** (73) while `f(3, **e)` did not. The two differ
only in which element comes first, so the defect was never about `**`: the guard
asked whether the argument list *began* with a star.

### What changed

The branch's guard now asks `PyArgListHasStarElem` — is there a `*`/`**`
ELEMENT anywhere at this paren depth — instead of testing the first token.
Element position is the whole predicate, because `f(a * b)` has a depth-0
`tkStar` too; a star is an element only at the head of the list or right after a
depth-0 comma. The scan follows the precedent at `pasparser_call.inc:137`.

Behind that guard, the two hand-rolled shapes are replaced by ONE loop
(`PyStarMixedForwardCall`) over positional / `*iterable` / `name=value` /
`**mapping` elements in any order and any number. This is a replacement, not an
addition: what stood there was a leading-`**` arm and a leading-`*` arm whose
trailing handling accepted exactly one star follower and refused everything else
by name — *"an argument after \*unpacking is not supported yet"*. Three of four
spellings failed, each for its own reason, which is what two parsers for one
concept looks like (`normalise-dont-special-case.md`). The target form was never
the difficulty: `PyStarForwardCall` has always taken a positional list and a
keyword dict, and every spelling is a different way of filling those two.

Both mirrors changed — `ParseFactorCore` (pasparser_expr.inc, `isNilPy`-guarded)
and `PyParseFactorCore` (pyparser.inc) — and both now call the same collector,
so the duplication across the two frontends shrank rather than doubled.

`pydict_merge_any` and not `TPyDict.update` for `**mapping`: `update` is four
overloads and `PyContainerCall1` resolves with `FindUMeth`, which answers the
FIRST declaration — that would have bound a dict to the `TPyList` arm. The free
function takes a Variant and decides at run time, which is also what `**` means.
The keyword dict is allocated lazily, so `f(1, *xs)` still reaches
`PyStarForwardCall` with a -1 dict and keeps its loud `pystar_no_kwargs` guard
instead of buying an always-empty allocation.

### Measured after (pxx vs CPython, every row identical)

| shape | before | after / CPython |
| --- | --- | --- |
| `f(3, **e)` | `expected expression` | 73 |
| `f(**d, b=7)` | `unexpected token` | 75 |
| `f(**d, **e)` | `unexpected token` | 75 |
| `f(a=1, **e)` | `unexpected token` | 71 |
| `f(*lst, 4)` | `an argument after *unpacking is not supported yet` | 43 |
| `f(3, *[], **e)` | `expected expression` | 73 |
| `g(1, *[2], **{"z": 9})` | `expected expression` | 129 |
| `g(1, y=2, **{"z": 9})` | `expected expression` | 129 |
| `f(**d)` / `f(*lst)` / `f(*lst, **e)` / `f(1,2)` / `f(b=7)` | 25/23/73/21/71 | unchanged |
| `h(1,2,3)` / `h(*[1,2,3])` on `def h(a, *rest)` | 3/3 | unchanged |
| `dict(**d)` | `{'a': 5}` | unchanged |

Evaluation order is source order across element kinds — the container calls are
hoisted as they are parsed — so `g(note(1), *[note(2)], z=note(3))` records
`[1, 2, 3]`, and a later `**e` overwrites an earlier `c=` the way CPython's dict
build does. Both are rows in the test.

### Gate

`test/test_nilpy_star_element_anywhere.npy`, 20 rows, oracled by running the
file under CPython 3 and diffing. Wired into **both** `test-nilpy` and
`test-core` — those two rules carry the same NilPy block, and the sibling
`test_nilpy_star_forward` is in both. `tools/check_test_wiring.py` is clean for
it (its 15 pre-existing `test_pyeval_*` / `test_softfloat_*` findings are
unchanged by this commit — verified by stashing).

`make compiler/pascal26` converged after 1 round; `tools/gate.sh quick` GREEN.

### Two adjacent gaps, measured and deliberately NOT built

Both were checked against the **pinned** compiler, so both are pre-existing:

- **`C(**d)` on an ordinary `__init__`** — named in this ticket's Gate section as
  a case to keep green; it was never green. `pascal26:N: error: expected
  expression` on the pinned binary too. The constructor path builds its own
  argument chain and needs the receiver prepended, which `PyStarForwardCall`'s
  signature does not take — a different lowering, not a routing change. Filed
  separately rather than grown into here.
- **Forwarding into a `**kwargs` COLLECTOR with named parameters beside it**
  (`def k(a, **kw)`): raises *"forwarded call has no value for parameter 'kw'"*.
  Identical on the pinned compiler for the spelling that reached it there
  (`k(**{...})`), and already documented in `PyStarForwardCall` as a considered
  deferral — the collector must receive the UNCONSUMED keys, there is no runtime
  helper for that remainder, and adding one means `compiler/builtin/**` and a
  pin. `k(1, **{"p": 2})` moved from a compile error to that same pre-existing
  runtime error, which is the two spellings meeting at one wall rather than a
  new failure.

## Log
- 2026-08-26 — resolved, commit 5c5115038.
