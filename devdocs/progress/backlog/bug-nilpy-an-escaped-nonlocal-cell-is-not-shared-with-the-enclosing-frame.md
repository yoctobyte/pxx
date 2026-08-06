---
summary: "An escaped closure's `nonlocal` cell is separate storage from the enclosing frame's own local, so the frame does not see the closure's writes and the closure does not see the frame's later writes. CPython shares ONE cell. Silent wrong values."
type: bug
track: N
prio: 55
---

# An escaped `nonlocal` cell is not shared with the enclosing frame

- **Type:** bug — Track N (Nil-Python frontend). Files: `compiler/pyparser.inc`,
  `compiler/builtin/pyeval.pas`.
- **Opened:** 2026-08-06, while fixing
  [[bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse]] — that
  ticket's crash is fixed; this is the residue it exposed.

## What is already correct

The common shapes match CPython exactly and are locked down by
`test/test_nilpy_nonlocal_escaping_closure.npy`: the escaped counter
(`bp()` → 1, 2, 3), two `counter()` results having independent state, several
`nonlocal` names in one closure, a float cell, `nonlocal` called while the parent
frame is alive, and the list-box idiom.

## What still diverges

CPython gives every closure over one frame — and the frame itself — **one shared
cell**. pxx binds a *fresh* 8-byte cell per closure, seeded with the value at the
moment the `def` statement is evaluated. So the two storages split whenever both
sides are used:

```python
# (a) the frame reads its own name after an escaped closure wrote it
def mixed():
    c = 0
    def bump():
        nonlocal c
        c += 1
    f = bump          # taken as a VALUE -> lifted to a bound-fn with a cell
    f()
    return c
print(mixed())        # CPython: 1     pxx: 0

# (b) the closure reads the name after the frame wrote it post-def
def mk():
    c = 0
    def peek():
        nonlocal c
        return c
    f = peek
    c = 99
    return f
print(mk()())         # CPython: 99    pxx: 8

# (c) two closures over one frame must share
def two_closures():
    c = 0
    def inc():
        nonlocal c
        c += 1
    def get():
        nonlocal c
        return c
    a = inc
    b = get
    a()
    return b()
print(two_closures()) # CPython: 1     pxx: 8
```

Note (b) and (c) answer **8**, not the seeded 0 — so the read path through a
`nonlocal` by-ref parameter is separately wrong, not merely stale. Worth a
`PXXDBG=a.ir` look at what the bound word actually is on that path before
assuming the cell is even reached.

**All three reproduce identically on `stable_linux_amd64/default/pinned`** — (b)
and (c) print 8 there too, and (a) was unreachable because the program segfaulted
first. So none of this is a regression from the cell fix; the fix turned five
crashes into four exact matches, and these are what is left.

## Why it is a bug and not a divergence

Ordinary working CPython code observes it and gets a wrong number with no
diagnostic — the upward-compatibility rule (`devdocs/dev/nilpy-semantics-divergences.md`)
puts that squarely in bug territory, and CLAUDE.md's escape rule says a silent
wrong value is filed in the owning lane rather than parked as a parity nicety.
Priority is 55 rather than higher because the shapes above all require taking the
nested def **as a value** and *also* using the enclosing name afterwards; the
dominant idiom (`return bump`, then call it) is correct today.

## Recommended fix

Promote the enclosing local to a **heap cell in the enclosing frame** when any
nested def that declares it `nonlocal` is lifted as a value, and have both the
frame's own reads/writes and the closure's by-ref parameter go through that one
cell. That is what CPython does, and it makes (a), (b) and (c) fall out together
rather than needing three patches.

The cheaper alternative — seed the cell lazily, or write back on closure release —
does not work: (c) has two live closures with no ordering between them, so
anything short of one shared cell will diverge on some interleaving.

Do the read path first, since 8-instead-of-0 says something is wrong before the
sharing question even arises.

## Gate
The three cases above diffed against CPython, plus
`test/test_nilpy_nonlocal_escaping_closure.npy` and
`test/test_nilpy_escaping_closure.npy` staying green, plus `make test-nilpy` and
self-host byte-identical. Fold the three into the former test once they pass.
