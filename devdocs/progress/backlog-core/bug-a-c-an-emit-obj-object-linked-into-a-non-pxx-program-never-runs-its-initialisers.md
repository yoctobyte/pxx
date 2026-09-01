---
track: A+C
prio: 55
type: bug
blocked-by: []
status: new
owner: ""
created: 2026-09-01
found-by: frankA (while fixing bug-a-c-a-shared-library-never-runs-its-initialisation; frankC found the shared-library half)
summary: "A pxx --emit-obj object linked into a GCC-built program never runs its file-scope initialisers, because they ride pxx's own entry stub and a gcc program has none. MEASURED: test/test_shared_lib.c as an object, `gcc host.c lib.o`, shared_c_from_data() returns NULL while the identical source as a pxx PROGRAM is correct and matches gcc. The parent ticket reasoned --emit-obj was fine because the object lands in a program with a pxx entry stub -- true only when the consumer is pxx-built, and linking into foreign programs is what --emit-obj is FOR. The .so half is fixed (DT_INIT); an object has no dynamic section to carry one and needs .init_array, which the linker aggregates and the host C runtime runs -- a different mechanism in a different writer."
---

# An --emit-obj object linked into a non-pxx program runs no initialisers

Split out of
[[bug-a-c-a-shared-library-never-runs-its-initialisation]], whose two shared
library halves are fixed (`7d1aed2b5`, `9b6ca0475`). This is the case that
ticket's reasoning excluded by a premise that holds everywhere except the
feature's purpose.

## Measured

```
$ pascal26 -Fulib/crtl --emit-obj test/test_shared_lib.c lib.o
$ gcc host.c lib.o -o host && ./host
obj from_data=(null) tag=pxx-c-shared
```

`shared_c_from_data` returns a file-scope `static const char *` initialised to
a string literal. The identical source compiled as a pxx **program** prints
`pxx-c-data` and matches the gcc oracle, and as a **.so** it now does too.

## Why the object case is different from the .so case

The C frontend emits `CompilePendingGlobalInits` at the start of `main`
(`cparser.inc`), so a translation unit with no `main` emits them nowhere. For
`--shared` that was fixed by emitting them into a DT_INIT thunk. **An object
has no dynamic section**, so there is nothing to point at: the standard
mechanism is a `.init_array` section holding a pointer to the initialiser
function, which the linker concatenates across objects and the host C runtime
runs before `main`.

So the work is:

- emit the initialisers into a real FUNCTION rather than inline (the .so thunk
  emits them inline, which an object cannot do — there is no entry to fall into)
- emit a `.init_array` section in the relocatable writer, with an
  `R_X86_64_64` relocation against that function
- decide whether the .so should ALSO move to `.init_array` for consistency, or
  keep DT_INIT. Both are correct; DT_INIT is what shipped.

## Scope note, and the reason this is not filed as "the same bug"

The `environ` half does **not** apply here: an object linked into a gcc program
gets glibc's `environ`, not ours, and `__pxx_run_initializers` is not wanted.
Only the file-scope initialisers are missing. Filing them together would
overstate what is broken.

## Not measured

Whether a pxx object linked into a **pxx** program is affected — the parent
ticket says it is not, because that program's entry stub runs the initialisers,
and nothing here contradicts it. Worth one run before the fix, since the fix
must not run them twice.
