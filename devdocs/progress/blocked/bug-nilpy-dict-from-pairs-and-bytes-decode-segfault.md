---
summary: "NilPy: `dict([(\"a\",1)])[\"a\"]` and `\"abc\".encode().decode()` both SEGFAULT (exit 139, core dumped) on ordinary one-liners"
type: bug
track: N
prio: 70
---

# `dict(pairs)` subscript and `bytes.decode()` segfault

- **Type:** bug (NilPy, CRASH) — **Track N**
- **Opened:** 2026-08-01, from a differential sweep of the string/list/dict
  method surface against CPython (133 cases, self-hosted binary at `c7d64813b`).

## Measured

```python
d = dict([("a", 1)])
print(d["a"])            # CPython: 1      pxx: SIGSEGV (exit 139, core dumped)
```

```python
b = "abc".encode()
print(b.decode())        # CPython: abc    pxx: SIGSEGV (exit 139, core dumped)
```

Both COMPILE cleanly (`ok: ... procs=1039`) and die at run time. Neither uses a
user class or any dunder — these are plain stdlib idioms.

## Why these rank high

A crash with no diagnostic is worse to chase than a wrong value, and both are
ordinary spellings a real program would hit:

- `dict(list_of_pairs)` is the standard way to build a dict from `zip()`,
  `.items()`, or parsed input.
- `.encode()` / `.decode()` round-tripping is the standard way to move between
  `str` and `bytes`, e.g. around any socket or file API.

They were filed together because they surfaced in the same pass. **They do NOT
share a cause** — the `dict()` half is now diagnosed below as a typecast, which
says nothing about `.decode()`. Diagnose that one separately.

## Cause of the `dict()` half — MEASURED: it is a TYPECAST, not a constructor

`dict(x)` is not lowered as a conversion at all. It parses as a **typecast to
TPyDict**, silently reinterpreting whatever object it is given:

| expression | result |
| --- | --- |
| `dict()` (no args) | **compile error** — not a valid cast |
| `dict(a_dict)` | works — an identity cast |
| `dict([("a",1)])` | **SIGSEGV** — a TPyList's header words read as TPyDict fields |
| `dict([1,2])` | **SIGSEGV** — same |
| `dict("x", 1, 2)` | compile error — arity checked, so 3 args are rejected |

The one-argument form being accepted while zero and three are rejected is the
tell: that is cast arity, not constructor arity.

**The sibling contrast is the strongest evidence** — every other container
conversion has real lowering and works:

| expression | CPython | pxx |
| --- | --- | --- |
| `list({"a":1,"b":2})` | `['a', 'b']` | `['a', 'b']` |
| `list("abc")` | `['a','b','c']` | `['a','b','c']` |
| `bytes([65,66])` | `b'AB'` | `b'AB'` |
| `dict([("a",1)])` | `{'a': 1}` | **SIGSEGV** |

So `dict` is simply the one missing a conversion, and falls through to the
class-typecast path that its name also matches. Same failure shape already
recorded in [[decide-class-namespace-scoping]] ("the RTL's `Text` record vs
tkinter's `Text` widget — a construction parsed as a record TYPECAST").

### Fix shape for this half

A pylib `pydict_from_pairs(l: TPyList): TPyDict` (walking each element as a
2-element sequence, like `pydict_fromkeys` at `pylib.pas:3373` already does for
keys) plus lowering `dict(x)` to it, and `dict()` to `TPyDict.Create`. The
typecast path must stop claiming the name — otherwise the next container added
inherits the same trap.

Unrelated but seen in the same check: `set([1,2,2])` prints `[1, 2]` where
CPython prints `{1, 2}`. Sets are backed by TPyList by design, so this is a repr
divergence rather than a correctness one — not filed.

## `.decode()` half — DIAGNOSED and FIXED 2026-08-01

Not a memory bug: a **missing overload**. `TPyBytes` declared
`decode(encoding)` and `decode(encoding, errors)` but no zero-argument form,
while Python's `b.decode()` defaults to utf-8. The bare call therefore bound to
the one-argument version with an UNINITIALISED `AnsiString` for `encoding` and
dereferenced it.

`b.decode("utf-8")` worked all along — which is exactly what hid it, and is the
contrast that identified it:

| expression | before |
| --- | --- |
| `b.decode("utf-8")` | `abc` |
| `b.decode()` | **SIGSEGV** |

Fixed by adding `function decode: AnsiString; overload;` to `TPyBytes`
(`compiler/builtin/pylib.pas`), returning `decode('utf-8')`.
`test/test_nilpy_bytes_decode.npy` is byte-identical to CPython and covers the
bare call, the explicit-encoding call, a round-trip through a variable, an
empty payload, and `bytes([...])`.

Native confirm: FPC seed build clean, self-host fixedpoint A==B==C, testmgr
--tier quick GREEN.

**Worth generalising** — a call with too FEW arguments bound to an overload and
crashed rather than being rejected. Whether that is specific to these pylib
`overload` declarations or a general arity hole in the NilPy call path is not
established here, and is worth its own check: if general, every optional-looking
pylib method has the same trap.

## Remaining work on this ticket

Only the `dict()` half (diagnosed above as a typecast, NOT fixed).

## Original first steps for the `.decode()` half (superseded)

`PXXDBG=a.ir:<proc>` on each (wrap in a `def` — the module-level dump prints
nothing), and `-dPXX_HEAP_DEBUG` to see whether the intermediate is being read
after free (freed bytes become `$DD` rather than a recycled neighbour's data —
`project_debug_heap_and_objtrace_flags`). Do not reason about the cause from the
symptom; this repo's expensive bugs are the ones where a plausible story went
unverified.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering `dict()` from a list of pairs (subscript, `len`, `in`, `.get`)
and `str.encode().decode()` round-tripping, including a non-ASCII byte if the
encoding path supports one.

## 2026-08-01 (later) — the "typecast" diagnosis is WRONG; blocked on a Track A bug

`.decode()` half confirmed fixed (b78988fe8, before this session) — `"abc".encode().decode()`
prints `abc`. Only the `dict()` half remained, and its recorded cause does not
survive measurement.

### It is not a typecast — `dict` is an ordinary overload set

```
$ pxx -e 'print(dict())'        error: no overload of dict matches these arguments
```

"no overload of dict matches" comes from `parser.inc`'s overload reporter, not
from a cast path. `compiler/builtin/pylib.pas` really declares:

```pascal
function dict(d: TPyDict): TPyDict;
function dict(const v: Variant): TPyDict; overload;
```

The table in the original diagnosis is still accurate as *observation* — 0 and 3
args rejected, 1 accepted — but it is **overload arity**, not cast arity, and
the conclusion drawn from it sent the fix at the wrong target.

### Actual cause: overload resolution ignores CLASS IDENTITY

`dict([("a",1)])` passes a **TPyList**. Resolution takes the first candidate
whose ARITY fits and never compares the argument's class to the parameter's, so
the TPyList binds to `dict(d: TPyDict)` and the body calls `d.keylist` on it —
one class's fields read through another's shape. Filed as
[[bug-a-overload-resolution-ignores-class-identity]], with a **plain-Pascal**
repro (two unrelated classes, wrong overload chosen, no NilPy involved). It is a
Track A bug affecting every overload set with class-typed parameters, not
anything specific to `dict`.

### What landed here, and why it does not fix it yet

`function dict(l: TPyList): TPyDict; overload;` added to `pylib.pas`, built on
`TPyDict.update(TPyList)` which already walks (key, value) pairs correctly
(verified: `d = {}; d.update([("a",1)])` gives `{'a': 1}`).

It is **declared last and is not selected yet**. Measured, and this is the part
that matters:

| declaration order | `dict([pairs])` | `dict(a_real_dict)` |
| --- | --- | --- |
| TPyDict first (as shipped) | SIGSEGV | works |
| TPyList first | works | **SIGSEGV** |

Ordering only MOVES the crash, because resolution is first-arity-match either
way. So there is no pylib-level fix, only a workaround that trades one broken
call for another — and per the no-compiler-appeasement rule the platonic
overload stays in place, unselected, `blocked-by` the Track A bug. When
resolution is fixed it starts being chosen with no further change here.

Confirmed no regression from adding it: `dict(a_real_dict)` and `dict([])` behave
exactly as before, `dict([pairs])` still crashes as before.

**blocked-by:** [[bug-a-overload-resolution-ignores-class-identity]]
