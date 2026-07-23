---
track: A
prio: 35
type: bug
---

# isNilPy: inline managed-string deref to a const param leaks the temp

Under `isNilPy`, passing a **managed-string dereference value** (`p^` where
`p: ^AnsiString`, or `PAnsiString(x)^`, or `rec.NamePtr^`) directly as a
`const AnsiString` argument materialises a hidden owning temp that is
**never released** — one leaked handle per call.

## Evidence

- Plain-Pascal (isNilPy=false) `p^`-to-const is CLEAN — a 100k-iter loop
  calling `eq(p^, 'x')` with `p: ^AnsiString` loses 0 bytes. So this is
  specific to the isNilPy managed-string-arg lowering, not a general
  deref bug.
- In the Pascal-written pyeval/pylib builtins (compiled under isNilPy for
  every NilPy program) it leaks. Confirmed dominant instance:
  `PyFindMethCI` did `PyEqCI(meths[i].NamePtr^, name)` and leaked one
  handle per method scanned per lookup — the top uforth-doloop per-exec
  leak (fixed at the call site in a0574d81 by binding to a skLocal;
  −97.5% per-iter). Two siblings (PyFieldGet kind-23, pystr_repeat_v)
  same shape (d1529d77).

## Why it only shows in builtins

NilPy user code has no raw pointers, so a `^AnsiString` deref only arises
in the Pascal-authored builtin units — which ARE compiled under isNilPy
(whole-compilation gate). That is why every reproduction is inside
pyeval/pylib and none could be written as a `.npy`.

## Root (for the fix)

In `IRLowerCallArg` / the call-arg marshalling, `AN_DEREF` is excluded
from the owning-arg-temp path (treated as a borrow — correct for a plain
managed-string variable's slot). But a deref that yields a managed-string
VALUE needing materialisation for a `const`/by-ref param DOES allocate a
temp (isNilPy path), and that temp is not registered for scope-exit
release. Either register it (SymIsHiddenArgTemp + skLocal so
EmitManagedLocalCleanup frees it), or route it through the same owning
path a non-lvalue managed-string call-result uses (which IS released —
`len(mk(i))` is clean).

Repro harness: instrument a builtin function with `f(somePtr^)` to a
`const AnsiString` param, compile a NilPy program that calls it in a loop,
profile with `pascal26 -g -dPXX_LIBC_HEAP` (the `-g` is essential — the
-O2 binary has no frame pointers and valgrind misattributes). Gate:
self-host byte-identical (this touches shared IR lowering) + the builtin
call-site binds can be removed once the root is fixed.

## Impact

Every isNilPy-compiled builtin that passes a managed-string deref to a
const param leaks per call. The three known hot sites are patched at the
call site; a root fix would remove the need for those binds and cover any
future sites. Not correctness — pure leak.
