---
slug: bug-n-a-callable-instance-crashes-with-star-args-as-a-key-or-through-a-variant
title: a callable instance crashes with *args, as a key, or through a variant
summary: >
  Three ways to call a user object through `__call__` crashed valid programs:
  `c(1, 2)` on `__call__(self, *args)` (SIGSEGV), `sorted(xs, key=KeyOf())`
  (SIGSEGV), and a `*args` `__call__` reached through a variant -- a
  decorator factory's result, `lru_cache(maxsize=None)(f)` -- (SIGSEGV).
  Found writing a functools shim, whose lru_cache and cmp_to_key are exactly
  these shapes. FIXED 2026-10-03 (frankuser).
track: N
type: bug
prio: 70
owner: frankuser
status: done
---

## Measured 2026-10-03 (frankuser)

### 1. `obj(...)` read its own arguments

PyMakeCallDunder parsed the argument list itself, one plain slot each, so a
`__call__(self, *args)` collector was handed a loose argument where it reads
its packed tuple. A keyword, a default or a `*seq` at the call site was not
understood either. `obj(...)` IS `obj.__call__(...)`, so the routine now binds
a fresh receiver (as before) and hands the rest to PyParseClassMethodCall,
the ordinary method-call path.

### 2. A callable instance in a key slot

`key=` is a raw callback Pointer (PyCallKey1 calls through it). A user object
is a pointer to the instance, so it was coerced into the slot as a CODE
ADDRESS and the program jumped into the object. PyCoerceCallableArgsIn now
rewrites an instance whose class defines `__call__` to the bound method
`obj.__call__`, the shape the dispatcher already calls (not for an EXTERNAL
callee, whose Pointer is a data pointer).

That alone answered `[3, 2, 1]` for ints and crashed for strings: the
dispatcher calls the pair through the function-object ABI, and
PyMethodUsedAsValue -- which decides that ABI by scanning for a `.name`
token not followed by `(` -- never sees `.__call__` in this spelling. So
`__call__` is now always normalised. The cost is boxing, paid only by a
class that defines `__call__`.

### 3. A `*args` `__call__` through a variant

PyCallDunder (pyeval) dispatched through PyHostCall, which passes arguments
one slot each. When the meth Flags word carries a star index, it now builds
the same `pybound_new_star` pair the getattr bridge builds and calls through
`pybound_callv<n>`, which packs.

### Verified

- test_nilpy_an_instance_call_takes_the_method_argument_list: `*args`
  forwarding and counting, defaults, keyword-only, `*seq`, keywords by name,
  a construction called directly.
- test_nilpy_a_callable_instance_as_a_key_is_called: sorted/max/min with a
  constructed and a named instance, ints and strings, reverse=.
- test_nilpy_the_functools_shim_matches_cpython: the variant case through
  lru_cache's decorator factory.

All three: byte-identical to CPython under -dPXX_HEAP_DEBUG and on i386,
census flat, control trips.
