---
track: N
prio: 60
type: bug
blocked-by: decide-sole-a-guard-for-unattended-sessions
---

# Subscripting a CALL RESULT: a string ignores the index, a chain drops the second

Two silent wrong answers on the same shape — a subscript applied directly to a
call result rather than to a name. Both are pre-existing
(`stable_linux_amd64/default/pinned` behaves identically).

## 1. A str-returning call ignores the index

```python
def f():
    return "abc"

print(f()[1])      # CPython: b     pxx: a
print(f()[-1])     # CPython: c     pxx: (empty)
print(f()[1:2])    # CPython: b     pxx: does not compile
```

The index is not merely wrong, it is **not applied** — every subscript yields
character 0. `f()[0]` is therefore "correct", which is exactly how this survives
casual testing.

## 2. A chained subscript drops the second index

```python
def f():
    return [["a", 1]]

print(f()[0][0])   # CPython: a          pxx: ['a', 1]
print(f()[0][1])   # CPython: 1          pxx: None

def g():
    return {"k": {"j": 7}}

print(g()["k"]["j"])   # CPython: 7      pxx: SEGFAULT
```

The first subscript applies and the second is discarded — so the value looks
like a container instead of an element. The dict-of-dict spelling crashes
instead.

## The boundary — it is the RECEIVER SHAPE, not the value

Everything below is **correct** today:

| form | |
| --- | --- |
| `s = f(); s[1]` | correct — via a NAME |
| `"abc"[1]` | correct — a literal |
| `xs[0][0]` on a name | correct |
| `"a-b".split("-")[1]` | correct — a builtin call returning a list |
| `f()["k"]` where f returns a dict | correct |
| `f()[1]` where f returns a list | correct |

So a call result is subscripted through a different path than a name, and that
path mishandles the STRING case and the CHAINED case. This is the shape recorded
in `project_nilpy_lvalue_vs_selector_path_must_both_know` — member/index access
has two parsers keyed on the receiver, and teaching one is not teaching the
other.

## Why it matters

`sorted(rows, key=...)[0]["name"]`, `line.split(",")[0][0]`, `f()[0][1]` are
ordinary code. It was found by a realistic CSV-parsing program, not by a probe:
the program computed four correct lines and then crashed on the fifth.

## Gate

`make test-nilpy` + self-host byte-identical, with a CPython-diffed test over a
call result subscripted by: a positive index, a negative index and a slice, for
a str-, list-, tuple-, dict- and bytes-returning call; the same chained two deep
(list-of-list, dict-of-dict, list-of-dict, dict-of-list); zero-argument and
argument-taking defs; a builtin call (`sorted`, `list`, `split`) in the same
positions; and the via-a-name spellings as controls. Assert the ELEMENT, never
just that it runs — every one of these bugs returns a plausible value.

## Recon 2026-08-09 — in parser.inc, BLOCKED on the sole-A guard

A subscript on a chained base is handled in `ParseClassRecordSelectors`
(`compiler/parser.inc:7421`), whose `tkLBrack` arm at **:7879** dispatches a
default property, a NilPy slice, and an array index. It is guarded by
`PyExprMode` in several places, so NilPy genuinely goes through it — and there is
no arm for indexing an ANSISTRING result, which matches the measured symptom
(the index is not applied at all rather than applied wrongly).

The function's own header comment is worth reading first when this is picked up:
it already had to learn `PyEvalOnce` because `f(args).m()` re-emitted the
receiver and ran it twice, and it notes "ParseLValueAST's suffix loop has always
dispatched this; the chained loop never did" about a different case. That is the
same defect class as this ticket, in the same function, recorded twice already.

`parser.inc` is a Track A file under the sole-A guard, which this unattended
session cannot clear — so this is filed and left. Sixth ticket behind
`decide-sole-a-guard-for-unattended-sessions`.
