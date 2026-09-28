---
track: N
prio: 50
type: bug
blocked-by: []
---
# uforth: every PYTHON-bodied word call leaked heap blocks (TYPE ~20 per call) — FIXED

**Summary:** FIXED 2026-09-27. There were two mechanisms in
`compiler/builtin/pyeval.pas`, and both apply to any code run through `exec`,
not only uforth's.

1. **Double reference on a fresh object.** A site that CREATES an object (it
   starts at refcount 1) then retained it again for the result slot. Nothing
   ever dropped the creator's +1. This covered list, dict, set and tuple
   literals, `range()`, `list()`, `reversed()`, genexps, and instances built by
   a class call or `__new__`. Those sites now adopt the construction reference
   (`PyBoxObjNew`).
2. **Method calls never freed their argument list.** In `ParseMethodCall`,
   `args` was never freed and `kwNames` was freed on only two paths, so every
   `x.m(...)` leaked both. Both are now freed in a `try … finally`.

Still retained twice: sites that box a CALL's result (the host-call return,
`int.to_bytes`, `str.encode`, `bytes(...)`). Nobody has measured their
ownership. The mechanism that would spring it is a callee that returns a fresh
object at refcount 1 and a boxing site that retains it again.

## Measured 2026-09-27
uforth 07ffdb1, `-dPXX_ALLOC_CENSUS`, `live=` at exit for 110 and 1110 input
lines of `1 2 TYPE CR`:

| compiler | tree | 110 | 1110 |
| --- | --- | --- | --- |
| pin v445 | caf21ac399f1 | 3680 | 24034 |
| HEAD | d96d826cd5fb @ 5581e895ee | 3680 | 24018 |
| fixed | 5581e895ee + patch | 2924 | 2929 |

Kept blocks per call before the fix were 10.7 × 56 bytes and 9.7 × 128 bytes.
They were found with a live-per-size census (a scratch-only change to
`CensusBins` in PXXFree) and then with `-dPXX_OBJTRACE`.

`test/test_nilpy_exec_body_objects_release.npy` is the regression row: 400
exec'd bodies. HEAD gives live=23407; the fix gives 176; the `keep` control
gives 925. The bound is 400.

Earlier standalone repros read FLAT for two reasons. `hold()`/`push()` in env
only resolve through a VM class (a bare function reports "no RTTI"). And
pyeval has no list comprehension, so a body using one errored before doing
any work. Check that the body RAN before you trust a flat census.
