---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`PY_MAX_LOCALS = 512` is too low for real modules — html5lib's constants.py needs between 513 and 1024 — but raising it is NOT the fix on its own: with the cap raised, two html5lib files SEGFAULT the compiler (exit 139, no diagnostic) at the default 8 MB stack. `ulimit -s unlimited` turns the crash back into a diagnostic, so it is a stack overflow the cap has been masking."
status: working
owner: frank2
---

# The module-locals cap hides a compiler stack overflow

- **Type:** bug (resource limit + robustness) — **Track N**
  (`compiler/pyparser.inc`), with a Track A flavour: the failure mode is a
  compiler crash on valid input.
- **Found:** 2026-08-17 by frank2, measuring what was behind the wall cleared by
  [[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]].
- **Measured at:** HEAD `65d26b24c`, native self-hosted builds (three of them —
  the shipped 512, and probe binaries at 1024 and 8192). Not `pinned`.

## The two facts, in the order they must be fixed

**1. The cap is too low.** `PY_MAX_LOCALS = 512` (`compiler/pyparser.inc:21`)
backs five arrays and is enforced at `pyparser.inc:26116` with
`Nil Python: too many inferred module locals`. `html5lib/constants.py` — which
most of html5lib imports — trips it. Bracketed by building the compiler twice:
it compiles cleanly at 1024, so the requirement is **between 513 and 1024**.

**2. Raising it exposes a segfault.** With the cap at 1024 *or* 8192 (identical
behaviour, so this is not a size artefact of the arrays themselves):

```
html5lib/filters/whitespace.py     → Segmentation fault (core dumped), rc=139
html5lib/treewalkers/__init__.py   → Segmentation fault (core dumped), rc=139
```

No diagnostic, no line number. It is a **stack overflow**, not a wild pointer —
under `ulimit -s unlimited` both files stop crashing and report an ordinary
compile error instead ([[bug-n-a-qualified-base-class-named-like-its-subclass-is-rejected-as-self-inheritance]]).
The default stack here is 8 MB. `constants.py` compiled *alone* at 1024 does not
crash, so the depth comes from the nested-import path, not from that one module.

So the shipped 512 has been acting as an accidental depth limiter. **Do not land
a bare constant bump**: it converts a clear diagnostic into a silent crash on
exactly the files it is meant to unblock, which is a regression in kind even
though it unblocks more input.

## Suggested order

1. Find and bound the recursion (the nested-import parse path is where the depth
   comes from — `constants.py` alone is fine, `whitespace.py`, which imports it
   through `..constants`, is not). Either make it iterative or give it an
   explicit depth guard that *reports* rather than crashes.
2. Then raise the cap. 1024 clears the measured requirement; a grown/dynamic
   table would be better than another fixed number, and there are five arrays
   dimensioned by it (`PyLocals`, `PyModuleLocals`, `PyPhantomNames`,
   `PyUnkBindNames`, `PyTopTargets`), so the memory cost is not free.

## Root cause of the overflow — found, and it is Track A, not N

*(frank2, 2026-08-18, at `25c077d54`.)*

The recursion is in `IRLowerAST`'s `AN_PAIR, AN_SEQ` arm (`compiler/ir.inc`). A
statement list is a **right-leaning cons chain**, and the arm lowered it by
recursing on the tail — **one frame per statement**. `IRLowerAST` is a very large
routine, so its frame is about **6 KB**.

Measured, not inferred:

| measurement | value |
| --- | --- |
| stack the crash needs (bisected by `ulimit -s`) | between **9.7 and 10.2 MB** |
| default stack | 8 MB |
| frame depth at the crash (`bt -1`, outermost frame number) | **1728** |
| ~10 MB / 1727 frames | ~6 KB a frame — consistent |

So it is **not runaway recursion**: it is a bounded chain that overshoots the
default by about 2 MB. That is why it presents as a crash on some files and not
others, and why the low `PY_MAX_LOCALS` masked it — the cap stopped those files
before lowering ever ran.

The crash site is **not** the cause and points nowhere useful: `IRLowerAddress`,
a leaf, 1727 frames from the chain that exhausted the stack. Under `gdb` at the
default limit it does not reproduce at all; forcing `ulimit -s 6144` first is
what makes it crash under the debugger.

Nothing here is NilPy-specific. NilPy reaches it first because an imported
module's body is **inlined into the importer as one chain** — a plain top-level
program's statements are lowered one at a time and never build the spine. That
is confirmed both ways: 8000 top-level statements do not crash the old compiler
even at a 1 MB stack, while **400 statements in an imported module do**.

## Fix (Track A — `ir.inc`, `defs.inc`)

Walk the spine iteratively; depth becomes O(block nesting) instead of
O(statements). Order is preserved exactly — lower `left0..leftk` then the tail,
then fold the `IR_BLOCK`s innermost-first, which is the order the recursion
produced. Left values are held on a global scratch stack (`IRSeqSpine`) used with
stack discipline, so a sequence nested inside another's statement reserves its
own slots above and cannot disturb the outer one. Overflow of that stack
**reports** — the property the recursive version could not offer at any size.

The recursive version also passed each inner `IR_BLOCK` through
`IRDropManagedStrResult` and `IRMarkStatementNode`; both are no-ops on an
`IR_BLOCK` (the first only rewrites a managed-string CALL result, the second only
tags a call), so dropping them changes nothing.

### Verified equal, not assumed equal

Self-host fixedpoint proves the new source is a fixedpoint — it does **not**
prove old and new agree on the same input. So six named files were compiled with
a pre-change compiler and the new one and the emitted binaries compared byte for
byte: `arrays.pas`, `bootstrap_features.pas`, `test_qualified_units.pas`,
`test_nilpy_sqlite_crud.npy`, `test_nilpy_module_identity.npy`,
`test_nilpy_qualified_base_same_name.npy` — **all identical**.

(A sweep over the whole `test/` glob was refused by the full-suite hook, which
was right: that is a regression run wearing a different hat. Six named files was
the allowed and sufficient form.)

### Controlled A/B on the actual failure

Two compilers differing **only** by this change, both at `PY_MAX_LOCALS = 1024`:

| file | before | after |
| --- | --- | --- |
| `filters/whitespace.py` | SIGSEGV (139) | `error: undefined variable (yield)` |
| `treewalkers/__init__.py` | SIGSEGV (139) | `error: no unit named six` |
| `filters/lint.py` | exit 1 | `error: no unit named six` |
| `constants.py` | exit 0 | exit 0 |

Every crash became a diagnostic. Those remaining errors are other gaps, not this
one.

## Regression test

`test/test_nilpy_deep_statement_chain.npy` + `test/nilpy_deepseq_mod.py` (400
statements), compiled under **`ulimit -s 1024`** — a deliberately small stack, so
400 statements catch a return of the recursion without checking in a 2000-line
file. Confirmed to discriminate: the pre-change compiler exits **139** on this
exact file at that limit, the new one exits 0 and prints CPython's answer. Wired
into both `test-nilpy` and `test-core`.

### One RED along the way, and it was the instrument

The first `gate.sh quick` came back RED on "the fixedpoint reached from PINNED
differs from compiler/pascal26". It was not the change: building the
`PY_MAX_LOCALS = 1024` probe left that binary on disk, and reverting
`pyparser.inc` afterwards did not rebuild it — so the tested binary was compiled
from sources that no longer existed. The classic stale-binary trap, and the gate
caught exactly what it is for. Reseeded from `pinned`, rebuilt, re-gated GREEN.

Worth recording because the failure text names a scary thing ("a
self-perpetuating miscompile") and the cause was a missing `make`. **A probe
binary built from temporarily-edited sources must be followed by a rebuild, not
just a `git checkout`.**

## Cap: still to raise, deliberately in a SEPARATE commit

The overflow is bounded first, per this ticket's own ordering constraint. Raising
`PY_MAX_LOCALS` is a second, independent change with its own gate, so that this
one's byte-identical A/B stays clean.

## Gate

`html5lib/constants.py` compiles; `filters/whitespace.py` and
`treewalkers/__init__.py` produce a *diagnostic or success*, never exit 139, at
the DEFAULT stack limit (do not gate under `ulimit -s unlimited` — that is the
instrument that proved the cause, not the fix). Plus `make test-nilpy` green +
self-host fixedpoint.
