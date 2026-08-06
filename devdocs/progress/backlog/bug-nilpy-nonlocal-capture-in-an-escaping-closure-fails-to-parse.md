---
track: N
prio: 65
type: bug
summary: "NilPy: a `nonlocal` write through an ESCAPED closure segfaults (re-measured 2026-08-06 — it used to be a parse error). The write itself faults; read-only captures and the list-cell workaround are fine."
---

# A `nonlocal` capture in an ESCAPING closure fails to parse at the call site

```python
def counter():
    n = 0
    def bump():
        nonlocal n
        n += 1
        return n
    return bump
bp = counter()
print(bp())          # pascal26:9: error: unexpected token  (near: bp)
                     # CPython: 1
```

**That was true when this was filed. It is NOT true any more — see the 2026-08-06
re-measurement below: it now COMPILES and SEGFAULTS.** The paragraph that follows
is kept as written, because the reasoning it records is still correct and is what
predicted the crash.

A compile error, not a wrong value — so this is the good failure mode, and it is
filed separately from
[[bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one]] (now fixed),
which was the silent one.

## Boundary

The same closure WITHOUT `nonlocal` parses and now runs correctly at every
arity. Called while the parent frame is still alive, the `nonlocal` form also
works — `return bump()` inside `counter` yields 1. It is specifically
`nonlocal` + escaping that fails, and it fails at the CALL site (`bp()`), not at
the def.

## Likely cause

`nonlocal x` makes that capture a BY-REF trailing parameter, so the write lands
in the enclosing frame (`pyparser.inc`, PyParseDefHeader:
`if PyBodyDeclaresNonlocal(...) then Procs[procIdx].Params[nOwn + j].IsRef := True`).
The value-closure path has no way to bind a by-ref parameter — `pyboundfn_bind`
stores a word, `pyboundfn_bind_var` a heap Variant slot, and the new
`pyboundfn_bind_obj` a retained object, none of which is "the address of the
enclosing local". Something in that mismatch leaves the resulting value typed
such that `bp()` no longer parses as a call.

Worth confirming with `PXXDBG=n.caps` and by dumping the type the name `bp`
ends up with, rather than assuming — the parse error is a symptom several
layers from whatever the real cause is.

## Note on semantics

Even once it parses, `nonlocal` through an escaped closure needs the captured
cell to OUTLIVE the enclosing frame — CPython gives every closure over the same
frame a shared cell, so two calls to `bump()` return 1 then 2, and two separate
`counter()` results have independent cells. Binding the enclosing local's
ADDRESS would dangle exactly the way the class capture did before
`pyboundfn_bind_obj`. The fix probably wants a heap cell per captured
`nonlocal`, bound like `pyboundfn_bind_var` already does, with the body's
by-ref parameter pointed at it.

## Gate

`make test-nilpy` + self-host byte-identical, plus the counter above and a
two-instance case (`c1 = counter(); c2 = counter()`) diffed against CPython.
The non-`nonlocal` shapes are already covered by
`test/test_nilpy_escaping_closure.npy` and must stay green.


## 2026-08-06 — RE-MEASURED: it no longer fails to parse, it SEGFAULTS

Found again while bughunting (a textbook counter closure), and the failure mode
has changed since this was filed. Measured on a self-hosted binary at
`54fbd2754` **and identically on `pinned`**, so this is not a regression of
today's work — something between the filing and now made it parse, and what is
left is precisely the dangling write the "Note on semantics" above predicted.

```python
def mk():
    c = 0
    def bump():
        nonlocal c
        c = 5          # <- SIGSEGV happens HERE, on the write
    return bump
f = mk()
print("before")        # prints
f()                    # Segmentation fault (exit 139)
print("after")         # never reached
```

The crash is on the **write**, not on the call or the bind: `print("before")`
runs, and a body that only assigns (no read, no return) is enough to kill it.

### Boundary, re-measured

| shape | verdict |
| --- | --- |
| escaping closure READING a local (`return c`) | works |
| escaping closure reading a PARAMETER | works |
| escaping closure mutating a captured LIST (`c[0] += 1`) — the usual Python workaround | works |
| `nonlocal` called while the parent frame is alive (`return bump()`) | works |
| **`nonlocal` write through an ESCAPED closure** | **SIGSEGV** |

So the by-value capture path is fine; only the by-ref `nonlocal` cell is wrong,
exactly as the note above reasoned. The read-only cases working is what makes
this narrow enough to fix confidently.

### Why the priority went 45 -> 65

The ticket was rated as a compile error — "the good failure mode". It is now a
hard crash on ordinary Python, with no diagnostic, at a place several frames
from the code that caused it. That is a materially worse thing to leave in the
backlog, and the rating should reflect what it does today rather than what it
did when filed.

The recommended fix is unchanged and is the one this ticket already reasoned
its way to: **a heap cell per captured `nonlocal`**, bound the way
`pyboundfn_bind_var` already binds a heap Variant slot, with the body's by-ref
parameter pointed at the cell instead of at the enclosing frame's local. That
also gives CPython's sharing semantics for free (two `bump()` calls on one
closure see one cell; two `counter()` results get independent cells), which the
Gate section below already asks for.

### Title

The slug still says "fails to parse", which is now wrong. Left alone on purpose:
renaming it would break the `[[...]]` links pointing here and rewrite the record
of what was actually observed when it was filed. The summary line and this
section carry the correct behaviour.
