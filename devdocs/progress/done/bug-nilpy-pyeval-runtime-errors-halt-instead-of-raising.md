---
prio: 50
track: N
type: bug
blocked-by: []
status: done
owner: claude-A
---

# pyeval's runtime errors `writeln` + `Halt` instead of raising

- **Type:** bug (NilPy; valid CPython refused) — **Track N**
- **Found:** 2026-08-09, while fixing
  [[bug-nilpy-none-returned-beside-a-container-is-an-unusable-nil-handle]].

```python
x = None
try:
    print(x[0])
except TypeError:
    print("caught")        # CPython: caught
```

pxx prints `pyeval: cannot subscript a non-container` and exits 1. The handler
cannot run, because there is no exception — the runtime called `Halt`.

```
compiler/builtin/pyeval.pas:1062
  begin writeln('pyeval: cannot subscript a non-container'); Halt(1); end;
```

`PySubscriptGet` alone has four such sites (non-container, string index out of
range, list index out of range, bytes index out of range); `grep -n "Halt(1)"
compiler/builtin/pyeval.pas` is the real list.

## Why it matters

It is the same shape as
`bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic`, whose fix
note states the rule already: a runtime fault must be a **catchable raise**, not
a halt, because a `try: ... except:` around it otherwise cannot run at all. Real
Python code guards subscripts with `except (TypeError, IndexError)`.

## Shape of the fix

Each site becomes `raise TypeError.Create(...)` / `raise IndexError.Create(...)`
with CPython's own wording (`list index out of range`, `'NoneType' object is not
subscriptable`). pylib's `PyTypeError` / `PyIndexError` helpers are the
precedent; check whether pyeval can reach them or needs its own.

Worth sweeping every `Halt(` in `pyeval.pas` and `pylib.pas` in one pass rather
than one site per ticket — they are one concept, and the ones left behind are
the ones that stay uncatchable.

## 2026-08-10 — the REPRO is stale; the TICKET is not. Do not close it on the repro.

The repro above now prints `caught` and exits 0, matching CPython — on the
current binary **and on `pinned`**. Two harder variants also catch:

```python
f = lambda v: v[0]        # a lambda body, not module code
xs = [None, None]; sorted(xs, key=lambda v: v[0])   # a key= callable
```

Both catch. So the *subscript* path no longer routes through pyeval at all —
most likely because lambdas are lifted to native code now (`f7bb7a9d3`,
"enforce arity on lifted lambdas, and reland the lift widening"), where
`project_nilpy_every_lambda_is_an_interpreted_pyeval_source_closure` used to
guarantee it did.

**But the defect the ticket is actually about is untouched:**

```
$ grep -c "Halt(" compiler/builtin/pyeval.pas   ->  29
$ grep -c "Halt(" compiler/builtin/pylib.pas    ->   3
```

and line 1062 — the exact site the ticket quotes — is still
`writeln(...); Halt(1)`. Every one of those is still an uncatchable exit rather
than a raise; the repro simply stopped being a way to reach one.

### What the next session should do differently

Do **not** start from the repro. Start from the `grep`, and for each `Halt`
site work out whether any NilPy program can still reach it — the ones that
can are the ticket, and the ones that cannot are dead code worth deleting on
the same pass. That reframing is the whole update here.

A cheaper framing if the sweep is too large: since these sites are unreachable
via the obvious paths, the priority question is no longer "catchable vs halt"
but "is this reachable at all". Both answers are progress; a stale repro is not.

**No code changed.** Ticket stays open with its original prio.

## Resolution (2026-08-11) — and the reachability question the ticket asked

Followed the 2026-08-10 instruction: started from the `grep`, not the repro, and
answered "can a NilPy program still reach this?" per site.

**Yes — and here is the shape that does it.** A lambda is lifted to native code
now, which is why the old repro went stale; the lift is REFUSED for a lambda
capturing a **local managed string**, and that body stays interpreted:

```python
def run():
    s = "abc"                    # a LOCAL managed string — a module global LIFTS
    f = lambda v: s + v[9]       # ...so this body runs in pyeval
    try:
        return f("xy")
    except IndexError:
        return "caught IndexError"
```

| | output |
| --- | --- |
| CPython | `caught IndexError` |
| `pinned` | `pyeval: string index out of range` — the handler never runs |
| HEAD | `caught IndexError` |

That distinction is the whole trick and belongs in any future repro: with `s` as
a module global the lambda compiles and the test proves nothing.

**Converted: the 14 sites that report a PROGRAM error** — subscript get/set,
slice-assign, del, and index-out-of-range on str/list/bytes — now raise
`IndexError` / `TypeError` with CPython's own wording (`list index out of
range`, `'NoneType' object is not subscriptable`, `... does not support item
assignment`), the type name coming from `pytype_name_v` so the message names
what the program actually passed.

**Deliberately NOT converted: the 15 that report an INTERNAL invariant** —
`no RTTI for attribute`, `vm has no method`, `host arity N too large`. Those
mean the COMPILER emitted something impossible, not that the program did
something wrong; dressing them as Python exceptions would let a compiler bug be
swallowed by an `except TypeError:` and reported as a program error. They stay
halts, and that is now a decision rather than an oversight. `grep -c "Halt("
compiler/builtin/pyeval.pas` is 15, down from 29.

Gate: `make test-nilpy` EXIT=0, `gate.sh quick` GREEN. New
`test/test_nilpy_pyeval_errors_are_catchable.npy`, whose header records the
local-vs-global trick so the next person can still reach these paths.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
