---
slug: decide-nilpy-import-rule-vs-a-cpyext-extension-module
track: U
prio: 75
status: decided
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

## DECIDED 2026-08-20 by the owner (Track U)

**Option 1, narrowed: an extension module is not a Pascal unit, and is therefore never
subject to the import rule at all. Detected by `PyInit_<name>`. The `_ext` name shape is
explicitly NOT a signal.**

Three parts, and the middle one corrects this ticket's own framing:

### 1. The quoted spelling stays, and calling it a workaround was wrong

The ticket argued that rewriting the tests to `import 'hello_ext.pas' as hello_ext` would be
a compiler-appeasement workaround. The owner overruled that framing: the quoted spelling is
**the rule, applied consistently**, not a dodge — *"i actually said quoted spelling is ok,
dotted spelling only if unambiguous. that's not a workaround but consistence."* It is
affirmed unchanged for reaching a Pascal unit. (The coordinator had carried the ticket's
framing instead of checking it against the rule as set; recorded because the mis-framing is
what made option 3 look disreputable rather than merely wrong for this case.)

Dotted-spelling-only-if-unambiguous is a **separate axis** and is deliberately NOT decided
here.

### 2. But an extension module never enters that rule's jurisdiction

The rule governs *how you reach a Pascal unit*. A cpyext extension module is a **Python
module whose body happens to be Pascal + C** — so it is not the rule's subject, and bare
`import <name>` is correct for it. This is not the rule bending; it is the rule not applying.

The owner's standard: *"we should honor the _ext syntax if that is de-facto standard and not
cheat around it."* The general form of that survives independently of `_ext` (see 3): bare
import of a C extension is **ordinary CPython**, not a spelling quirk — every accelerator in
the stdlib is reached that way — so upward-compat genuinely requires it.

### 3. `_ext` is NOT a de-facto standard — MEASURED, and it is not close

The conditional in the owner's instruction was tested rather than assumed. Prediction written
down first (CPython uses a LEADING underscore; `_ext` is not a convention), then measured on
CPython 3.12.3:

```
stdlib lib-dynload   48 extension modules   39 leading _   0 ending _ext
statically builtin   61 modules                            0 ending _ext
third-party .so      99 extension modules   31 leading _   0 ending _ext
              total 147 real extension modules             0 ending _ext
```

`_socket`, `_json`, `_ssl`, `_pickle`, `_decimal`, `_imaging`, `_psutil_linux`… The six test
units (`hello_ext`, `argerr_ext`, `container_ext`, `cyadd_ext`, `fmt_ext`, `markupsafe_ext`)
are **test-local naming invented by the cpyext suite's author**, not borrowed from upstream.

So the owner's conditional resolves to: **there is nothing in the name to honor.** Keying
bare-importability on a name suffix is rejected — it would be a coincidence-predicate
(see [[project_a_proxy_standing_in_for_the_real_question]]) built on a convention that does
not exist.

### 4. Detection: recorded fact preferred over inferred proxy

`PyInit_<name>` is the criterion. Two sub-shapes, and the ticket treated them as one option:

- **(a) grep the unit's `uses` clause `.c` files for `PyInit_<lo>` at resolve time** — works,
  costs nothing structurally (the resolver already holds `pasRefusedPath`; see
  `compiler/parser.inc:34223`, where the refusal fires *after* the unit has been found and
  read), but the compiler is now grepping C to make a Pascal decision, and it is an inferred
  proxy.
- **(b) the unit DECLARES itself an extension module; `PyInit_<name>` VERIFIES the claim** —
  a recorded fact rather than a proxy, and a missing/misnamed `PyInit_` becomes a
  *diagnostic* instead of a silent mis-resolution.

**(b) is preferred**, per the repo's own standing lesson that a recorded fact beats an
inferred one. (a) is acceptable if (b) proves to need more machinery than it is worth; the
implementer decides and states which, in the ticket.

Options 2 (an `-Fpyext` search root) and 3 (migrate the tests) are **rejected**: 2 invents a
flag CPython has no concept of, which fails upward-compat one level up; 3 would leave the
cpyext suite not testing its own subject.

### What this unblocks

The six cpyext jobs keep their bare imports AND their subject. Implementation re-filed as
`feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit`.

**Filed-work note:** the refusal site is in the SHARED `compiler/parser.inc`, so this is
Track A file-ownership despite being N-flavoured work. It must NOT be dispatched while
another agent holds `parser.inc` — as of this writing frank3 is mid-carve on
`ParseFactorCore` in that file.
