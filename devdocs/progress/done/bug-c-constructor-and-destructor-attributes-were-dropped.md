---
track: C
tags: [c, attributes, object, init_array, rump, silent-miscompile]
prio: 5
type: bug
blocked-by: []
summary: "__attribute__((constructor)) and ((destructor)) were parsed and dropped: no .init_array entry in an --emit-obj object, no call in a pxx-linked program. rump (-DRUMP_USE_CTOR) registers every component and module that way, so a pxx-built rump kernel would boot with none. Now the object's init/fini thunk calls them (also under --freestanding), and a program calls them from main's init proc / the finalizers."
status: done
owner: claude-dupwt
---

# Constructor and destructor attributes were dropped

rump's silent gap S2 (Rainyday docs/rump-pxx/README.md): with
`-DRUMP_USE_CTOR`, `RUMP_COMPONENT()` and `_MODULE_REGISTER()` expand to
`static void f(void) __attribute__((constructor));` plus a definition, and
`rump_init()` sees only the components those constructors registered. pxx
accepted the attribute and emitted nothing. The object had no `.init_array`
entry, `f` was never called, and nothing said so.

## Fix

- The lexer files `constructor`/`destructor` on the next token, as it does
  `weak`. `CAttrFlags` widens to Word (bits 8..9), because its 8 bits were
  all taken.
- The parser registers the function (`CRegisterCtor`) from either the
  prototype or the definition. rump puts the attribute on the prototype
  only.
- `--emit-obj` / `--shared`: the init thunk (the object's `.init_array`
  slot) calls the constructors after the file's initialisers, in
  declaration order. The fini thunk calls the destructors in reverse, before
  the Pascal finalizers. Both apply under `--freestanding` too, as with gcc.
  The freestanding "needs run-time initialisation" refusal still looks only
  at the initialisers.
- A program pxx links: main's init proc (`__pxx_c_main_init`) calls the
  constructors, and the destructors join the finalizers, which run
  last-first at exit. A constructor defined after `main` is refused by name,
  since the init proc is emitted before main's body.

Priorities (`constructor(101)`) are accepted but not honoured across objects:
all of an object's constructors run at its one `.init_array` slot.

## Proof

`test/c_attribute_constructor.c` matches gcc's output (order, prototype-only
attribute, both spellings, destructors at exit). It is tested whole at -O0
and -O2, as an object under a gcc main, and as a `--freestanding` object
under a gcc main.
