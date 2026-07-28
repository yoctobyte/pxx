---
track: N
prio: 70
type: bug
---

# `pydict_v` handed back a BORROWED dict — use-after-free, heap corruption

`for option, value in options.items()` where `options` came out of another dict
unboxes the variant through pylib's `pydict_v`, which returned the dict INSIDE
the variant as-is. `pylist_v`, its sibling, returns a COPY — so the caller's
release of the temporary is harmless there, and fatal here: it dropped the
variant's own reference and freed a live dict.

The write that follows lands in a freed block, which on the native allocator is
a free-list link — so the crash surfaces much later, inside `PXXAlloc`, in
whatever code happens to allocate next. In songformatter's settings.py it looked
like `label.grid(row=row, column=0, sticky="e")` crashing (string concat inside
`TkiOptInt` → `PXXStrConcat` → `PXXAlloc`), three statements and two library
layers away from the cause.

## Repro (12 lines, deterministic)

```python
D = {"UI": {"a": 1}}
def walk():
    n = 0
    for section, options in D.items():
        for option, value in options.items():
            n += 1
    return n
print(walk()); print(walk())
```

Under `-dPXX_LIBC_HEAP` + valgrind: "Invalid read/write of size 8, 8 bytes
inside a block of size 72 free'd", freed from `PXXObjRelease` ←
`PyVarSlotClear` ← `PyObjFinalize`.

## Fix

`pydict_v` retains the object it hands back, so the reference leaving the
function is a second OWNER. (The alternative — copy like `pylist_v` — costs a
dict copy per loop and changes mutation semantics.)

## Technique worth reusing

`-dPXX_LIBC_HEAP` puts the pxx heap on libc malloc, which makes valgrind see
every allocation. A native-allocator crash that makes no sense at the crash site
is a use-after-free until proven otherwise, and this is how to see it.

## Gate

`test/test_nilpy_membership_bool_return.npy` (third section: two passes over a
dict of dicts), `make test-nilpy`, self-host fixedpoint.

## Log
- 2026-07-28 — resolved, commit 5174d000e.

## Resolution

Already fixed by earlier NilPy work that did not move the ticket. Re-verified
2026-07-28 at 5174d000e: the repro above matches CPython exactly.
