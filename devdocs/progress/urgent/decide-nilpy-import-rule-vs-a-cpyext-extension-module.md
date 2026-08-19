---
slug: decide-nilpy-import-rule-vs-a-cpyext-extension-module
track: U
prio: 75
status: urgent
---

# The NilPy import rule made `import hello_ext` — CPython's own spelling for a C extension — unspellable, and six cpyext jobs went red

Found triaging `regression-cascade-21f098e32a95` (13 jobs). Six of the 13 are one
cause and it is **not** a mechanical migration; it is a collision between two
rules we hold at the same time.

## What happens

```
$ pascal26 -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_hello.npy out
pascal26:6: error: import: hello_ext is the Pascal unit test/nilpy_units/hello_ext.pas,
  not a Python module — a bare NilPy import resolves to Python (.py/.npy) only.
  To reach the Pascal unit, name it with its extension:
  import 'hello_ext.pas' as hello_ext
```

Red jobs, all the same line: `test_cpyext_hello`, `test_cpyext_args_errors`,
`test_cpyext_containers`, `test_cpyext_markupsafe`, `test_cpyext_errformat`,
`test_cpyext_cython`.

## Why this is a decision and not a fix

`import hello_ext` is **exactly what a CPython program writes** to load a C
extension module. It is the spelling the whole cpyext campaign exists to make
work — `test/nilpy_units/hello_ext.pas` is not "a Pascal unit standing in for a
Python module", it IS the extension module's PXX-side body (it pulls
`./hello_ext.c` with its `PyMethodDef` table and `PyInit_hello_ext`, in real
CPython boilerplate shape, deliberately).

So the two rules disagree:

- **The import rule** (`decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit`,
  user 2026-08-19): a bare NilPy import resolves to Python only; a Pascal unit is
  reached by naming it with its extension.
- **The N charter**: NilPy is upward compatible with CPython — *if code works on
  CPython, it must work on NilPy.* A C extension imported by its bare module name
  is the most ordinary CPython code there is.

Rewriting the six tests to `import 'hello_ext.pas' as hello_ext` would make them
green and would be a **workaround**: it hides the conflict behind a spelling
CPython does not have, in the exact tests whose subject is CPython
compatibility. Under "platonic code — no compiler-appeasement workarounds" that
is not the move, so the tests are left as they are and this is filed instead.

## Options

1. **A cpyext extension module is not "a Pascal unit"** — teach the import
   resolver that a unit whose C side defines `PyInit_<name>` is a Python
   extension module and stays reachable by bare import. Narrow, keyed on the
   thing that actually makes it a module, and leaves the rule intact for every
   ordinary unit. *Recommended.*
2. **An extension search root** — a `-Fpyext`-style root (or a marker directory)
   whose units are module-shaped by declaration, bare-importable, and no other.
   More explicit, more machinery, and someone has to say which root.
3. **Migrate the tests to the quoted spelling** — cheapest, and it makes the
   cpyext suite stop testing what it was written to test. Recorded so the trade
   is visible; not recommended.

## What the answer unblocks

Six red gated jobs, and the shape of every future `import <extension>` — this is
the first place the import rule and the upward-compat charter have actually met.

*Filed by frank2-C during cascade triage; not claimed. Three sibling reds in the
same cascade WERE ordinary migrations (they import genuine Pascal units) and are
already fixed.*

## Added 2026-08-19 by the coordinator — this decision now also gates PINNING

Six of the ten reds in Track T's `pin_shadow` at 19:34:58Z are the cpyext jobs blocked on
this decision. `pin_shadow` reports `would_pin: false` off a raw red count, so **until this
is answered the shadow can never say yes**, and every pin is taken over its objection. Pin
v366 was (the reds were all older than v365, so the pin was defensible — but the pattern is
not). Filed separately as
[[bug-t-the-pin-shadow-cannot-clear-while-its-reds-are-older-than-the-pin]].

That does not make the decision more urgent on its own merits, and it must NOT be rushed for
it — the whole point of the ticket is that the green route deletes the tests' subject. It
does mean the cost of leaving it open is higher than "six tests are red": it is also "the
automated pin gate is permanently false".
