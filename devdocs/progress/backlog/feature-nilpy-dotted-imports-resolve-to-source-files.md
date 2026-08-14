---
track: N
prio: 65
type: feature
summary: "A dotted import (`from neuzelaar.core.bus import Bus`) resolves ONLY to a hand-written `mimic_<mangled>` shim unit; it never looks for the source file `neuzelaar/core/bus.py` on disk. FLAT sibling imports already work for both .py and .npy. So NilPy can compile a single file plus shims, but cannot compile a multi-module Python PACKAGE — 89 of 150 failures in the neuzelaar census, the single largest blocker by 3x."
---

# Dotted imports never resolve to a source file, only to a shim

- **Type:** feature — **Track N** (`compiler/pyparser.inc` import resolution).
- **Found:** 2026-08-14, re-baselining
  [[feature-nilpy-thirdparty-libraries-as-targets]] against the neuzelaar corpus.

## The boundary, measured

Both halves of this were checked with a purpose-built minimal package, not
inferred from the corpus:

| shape | result |
| --- | --- |
| `from bus import Bus` (flat sibling `bus.py`) | **works** |
| `import bus` (flat sibling) | **works** |
| `from bus2 import Bus` (flat sibling `bus2.npy`) | **works** |
| `from mypkg.sub.bus import Bus` (real package on disk) | **`no unit named mypkg_sub_bus and no shim mimic_mypkg_sub_bus`** |

So single-file compilation is fine and *flat* multi-file compilation is fine.
What is missing is exactly one thing: a dotted path is never tried **as a file
path**.

## Why it looks like a shim system rather than a bug

`feature-nilpy-dotted-package-imports` mangles `a.b` onto `mimic_a_b` because a
Pascal unit name cannot contain a dot, and it was built to reach **shims** —
hand-written stand-ins for third-party libraries like `mimic_reportlab_pdfgen`.
That is the right mechanism for `import reportlab`, and
`test_nilpy_dotted_package_import.npy` pins it working.

It is the wrong and only mechanism for `import neuzelaar.core.bus`, where the
source is sitting right there in the tree. Every intra-project import in a real
app therefore asks for a shim that will never exist, and the diagnostic
faithfully says so.

## It is NOT a masked compile error

The obvious alternative explanation — the imported module fails to compile and
the failure is reported as "not found" — was ruled out. A **clean** two-module
package whose imported module compiles standalone fails identically, and so does
one whose imported module has a deliberate error: byte-for-byte the same
message. The resolution never gets far enough to care.

## Why this is the schedule-decider

Census of the 168 git-tracked files in `~/neuzelaar2`, compiled with HEAD:

| failure kind | files |
| --- | --- |
| **intra-project imports** (its own modules) | **89** |
| stdlib imports (`enum`, `argparse`, `datetime`, `contextlib`, `threading`, `importlib`) | 28 |
| third-party imports (`pytest`, `yaml`, …) | 19 |
| language/frontend gaps | 14 |

18 of 168 compile today (11%). The parent ticket's schedule named `@dataclass`
as the construct that "decides the schedule" — measured, dataclass gaps are
**5 files**. Intra-project imports are **89**, and they are one mechanism, not
89 bugs.

Note the second-order effect: a file that fails on its first import is not
*compiled*, so its remaining constructs were never exercised. **The language-gap
column is a lower bound and will grow once imports resolve** — which is an
argument for doing this first, not an argument against the number.

## Design notes

- **Search order matters and is a real decision.** Source-first means a project
  module shadows a shim of the same dotted name; shim-first means the opposite.
  Python's own answer is `sys.path` order, and the nearest analogue here is
  "the compiled program's own tree wins over a bundled shim" — which also
  matches [[feedback_own_language_first_name_resolution]] in spirit. Worth
  stating explicitly in the implementation rather than falling out of the code.
- `__init__.py` needs a policy: Python executes it, and a package whose
  `__init__.py` re-exports names (`from .bus import Bus`) is extremely common —
  neuzelaar's `neuzelaar/core/config/__init__.py` is exactly that shape.
- Relative imports (`from .bus import Bus`, `from ..core import x`) are a
  separate shape from absolute dotted ones and should be scoped explicitly,
  not assumed to fall out.
- The mangled unit name is a flat namespace: `a.b_c` and `a_b.c` both mangle to
  `a_b_c`. Fine today; worth a diagnostic if it ever collides.

## Gate

A real package on disk compiles from its entry point: `from a.b.c import X`,
`import a.b`, `import a.b as ab`, and a package whose `__init__.py` re-exports.
`test_nilpy_dotted_package_import.npy` still passes (shims must keep working).
A new test with a genuine multi-directory package under `test/nilpy_units/`.
Re-run the census: the intra-project column should collapse.
