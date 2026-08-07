---
summary: "An escaped closure's `nonlocal` cell is separate storage from the enclosing frame's own local, so the frame does not see the closure's writes and the closure does not see the frame's later writes. CPython shares ONE cell. Silent wrong values."
type: bug
track: N
prio: 55
status: done
owner: claude-A-N
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

## 2026-08-06 — the `8` was NOT a cell problem, and it is fixed

This ticket said cases (b) and (c) "answer 8, not the seeded 0 — so the read path
through a `nonlocal` by-ref parameter is separately wrong". That was the right
observation and the wrong explanation, and the difference matters because the
explanation pointed at the cell.

Measured instead of reasoned. Two programs with an IDENTICAL closure body:

```python
def mk():
    c = 41
    def peek():
        return c
    return peek          # -> 41, correct
```
```python
def mk():
    c = 41
    def peek():
        return c
    f = peek             # <- through a LOCAL
    return f             # -> 5580016 : a raw ADDRESS
```

`nonlocal` is not involved: the plain-capture form printed a heap address, and the
`nonlocal` form printed the constant 8. `return inner` was right, `f = inner` was
wrong. Dumping both with `PXXDBG=a.ir:mk` showed why — the return form emits
`pyboundfn_new` and a bind chain; the assignment form emits a different helper
with the bare code address and no chain at all.

**Root cause:** `return inner` goes through ParseFactor, which has always called
`PyNestedDefClosureValue`. `f = inner` goes through `PyMakeFuncValueFor`, which
built `pybound_new(addr, nil, isFunc)` and **never consulted it** — so no captures
were bound and the callee read them out of the dead parent frame. Pre-existing:
both wrong answers reproduce on `stable_linux_amd64/default/pinned`.

**Fixed** by trying `PyNestedDefClosureValue` first in `PyMakeFuncValueFor` and
boxing its result with the existing `PyBoxCallableValue` (the bind chain hands
back a pointer; this function must return a tyVariant). Tried FIRST because the
overload/wrapper logic below it can replace `pi` with a synthesized wrapper that
has no `PyDefTokOf`; and `PyNestedDefClosureValue` answers -1 when there is
nothing to bind, so an ordinary def still takes the plain path underneath.

All three now match CPython, and `test_nilpy_nonlocal_escaping_closure.npy` covers
the assignment path for a plain capture, a `nonlocal` read, and the counter.

## What is left — and it IS this ticket's actual subject

With the garbage gone, the cases below now print the **honest stale value** rather
than nonsense, which is exactly the cell-not-shared divergence the ticket
describes:

| case | CPython | pxx now | pxx before |
| --- | --- | --- | --- |
| (a) frame reads its own name after an escaped closure wrote it | 1 | 0 | 0 |
| (b) closure reads the name after the frame wrote it post-def | 99 | 0 | **8** |
| (c) two closures over one frame must share | 1 | 0 | **8** |

So the remaining work is the single thing the ticket recommends and nothing else:
**one shared heap cell** between the enclosing frame and every closure over it,
instead of a fresh cell seeded per closure. The "do the read path first" advice
above is now spent — that was this fix.

Also still open, and narrower than it looks: a CLASS capture declared `nonlocal`
keeps `pyboundfn_bind_obj`, so it has no writable cell at all. Not reachable from
any test today; recorded here rather than guessed at.

## 2026-08-07 — FIXED: one shared frame cell

Implemented the ticket's own recommendation, and (a), (b), (c) did fall out
together as it predicted.

**Shape.** A local (or parameter) that any def nested in the body declares
`nonlocal` is promoted to a **frame cell**: a hidden pointer local holding one
heap slot allocated in the prologue. The name keeps its symbol and its LOGICAL
type — everything that asks "what does this name hold" still gets the right
answer — and only the ACCESS shape changes: every read and every write becomes
`hidden^` (`SymCellPtr`, new symbol side-table). Two properties make the rest
free:

- `IRLowerAddress` of an `AN_DEREF` collapses to the pointer, so passing such a
  name to the by-ref parameter a `nonlocal` capture already gets hands the
  callee **the frame's own cell**, not a copy;
- the closure binder can therefore bind the plain pointer
  (`pyboundfn_bind`) instead of `pyboundfn_bind_cell`'s fresh per-closure copy,
  and the cell outlives the frame exactly as the old copy did.

Sites: `PyPromoteNonlocalCells` / `PyPromoteCell` / `PyCellPromotable` (new),
`PyMakeIdent` + `PyMakeCellPtr`, both closure binders, the nested-def capture
registration, and two PyExprMode-gated rewrites in the shared parser (the
ordinary ident read in `ParseLValueAST`, and the direct-call capture actual in
`ParseFactorCore`). Runtime: `pycell_new` in `pyeval.pas`.

**Two things measurement caught that reasoning would not have:**

1. A read-only sibling closure (`def get(): return c` beside `def inc(): nonlocal
   c`) printed an address. Its capture parameter had been declared by-VALUE by
   the enclosing body's local-typing TRIAL parse, which registers the nested
   def's Proc *before* any cell exists — so the real parse found
   `procIdx >= 0` and skipped the whole by-ref decision. Fixed by re-applying it
   in an `else` arm, where the promotion is known. The `nonlocal` arm never had
   the problem because it is token-based and so agrees across both passes.
2. An unannotated PARAMETER is a **variant**, and variants are the common NilPy
   local. A cell therefore had to be 16 bytes with a zeroed `{tag, payload}`,
   like `pyboundfn_bind_var`'s slot — and a variant param's `IsRef` is merely
   this dialect's calling convention, not an alias for another frame, so it is
   the one by-ref shape that may still take a cell.

**Not promoted** (left on the old copy-per-closure path, unchanged): managed
strings, records, arrays, and class instances — a class capture would need the
retain that `pyboundfn_bind_obj` does, which is the residue the previous
write-up already recorded and it is still open.

**Verified**, on a self-hosted build at this commit: `test_nilpy_nonlocal_-
escaping_closure.npy` — extended with all three ticket cases plus a read-only
sibling, a parameter, and an escaping pair — diffed **byte-identical against
CPython**, as do `test_nilpy_escaping_closure`, `test_nilpy_global_scope_binding`
and `test_nilpy_selfassigned_comprehension`. `tools/gate.sh quick` GREEN
(self-host fixedpoint + testmgr quick).

## Log
- 2026-08-07 — resolved, commit c29ce3031.


## 2026-08-07 (later) — a LEAK this fix introduced, found and fixed the same day

Caught by measuring my own change rather than by a test, and worth recording
because the shape is instructive: the fix was correct and still cost memory in a
case that needed nothing at all.

A `nonlocal` capture reached ONLY through a direct call never needed a cell. The
call site passes `@c` — the address of the enclosing slot — and the by-ref
parameter writes straight through it, so the frame and the callee already shared
one storage, for free, before any of this. The cell exists solely because a def
taken as a VALUE outlives the frame and a stack slot cannot.

Promoting on the presence of `nonlocal` alone therefore allocated a heap cell per
**activation** of the enclosing function, never freed, in frames where no closure
was ever created:

```python
def counter():
    c = 0
    def bump():
        nonlocal c
        c += 1
    bump()          # direct call only — no closure escapes
    return c
```

2,000,000 calls: **1 MB on `pinned`, 48 MB at HEAD.** A leak in a shape that
previously did not allocate at all.

Fixed by `PyBodyLiftsANestedDef`: promotion is skipped unless some def nested in
the body is taken as a value — assigned, returned, or passed — rather than only
called by name. Conservative in the safe direction, because the two failure modes
are not symmetric: over-answering True costs the old leak, under-answering gives
wrong VALUES. So a name counts as a call only when immediately followed by `(`;
`return bump`, `f = bump` and `xs.append(bump)` all read as values, as does
anything else.

Back to **1088 kB, exactly `pinned`'s number**, and the six shared-cell cases
plus every other closure test still diff byte-identical against CPython. Both
shapes are now pinned by name in
`test_nilpy_nonlocal_escaping_closure.npy` (`direct:` and `both:`).

The leak that REMAINS on the escaping path is not this one: it is the pre-existing
[[bug-nilpy-bound-fn-closure-objects-are-never-freed]], which the cell now joins
(~23 bytes of ~227 per closure — measured and recorded there, since the two have
one lifetime and want one ownership model).
