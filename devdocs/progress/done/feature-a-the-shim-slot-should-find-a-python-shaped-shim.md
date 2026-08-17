---
slug: feature-a-the-shim-slot-should-find-a-python-shaped-shim
track: A
prio: 70
status: done
owner: frank2
---

# The shim slot is Pascal-only; a Python-shaped shim has nowhere honest to live

Implementation of `decide-how-python-shaped-shims-should-be-shipped`, decided by
Rene 2026-08-17. Direction is settled; this is the work.

## Why it is urgent rather than tidy

`six` gates **15 of 58 files** in the NilPy corpus ladder — the single largest
blocker, ahead of webencodings-as-a-unit (7), `xml_dom` (3) and `warnings` (3).
Track N measured the ladder at HEAD and the walls are missing modules, not
frontend bugs: three N fixes landed 2026-08-17 and the compile count did not move
(4 pinned, 4 HEAD). Nobody can build `six` until this lands.

## The defect

`PyMimicShimExists` (`compiler/parser.inc:33206`) probes exactly two paths:

    lib/pcl/mimic_<name>.pas
    lib/rtl/mimic_<name>.pas

`six`'s entire content is Python aliases — `text_type = str`. Expressing "the
`str` type object as a value" from Pascal is not something any shim does. A NilPy
`.py` serves it perfectly and was verified byte-for-byte against CPython by Track
B; it simply has nowhere to live under a name that says what it is.

The Pascal-only slot is an accident of when the lookup was written, not a design.

## What to do

Probe `mimic_<name>.py` alongside `mimic_<name>.pas` in the same roots, and load
it through the NilPy path. Keep the two spellings in one lookup rather than
growing a second mechanism beside it.

## Why NOT `lib/**/six.py`

It works, and it is refused on the owner's ruling that **the tree must say what
each shim is**:

> *"resolution is a MAPPING, and the unit keeps OUR name… no file in the tree
> carries the upstream name."* (Rene, 2026-07-26)

> *"not sneakily load other shims."* (Rene, 2026-08-17)

A file named `six.py` satisfying `import six` while the build reports no shims is
a dishonest tree, independent of any flag. **Do not harden `--no-shims` as part of
this** — it means "unsupported: we provide no shims", nothing is guaranteed past
the opt-out, and complicating the common path to defend an opt-in audit flag was
explicitly rejected.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`. A `.npy` test importing a module
served by a `mimic_<name>.py`, and the same import failing under `--no-shims` —
which is the observable proving the shim is visible AS a shim rather than
masquerading as a library module.

## 2026-08-17 (frank2, Track A) — RESOLVED. The cause section was stale; the real gap was narrower and deeper.

Premises re-derived before writing code, per the standing rule. **Every symptom
reproduced; the stated cause did not hold.**

### What was already true

A `mimic_<name>.py` in a library root **already loaded and ran**. Dropped
`lib/rtl/mimic_probe6.py`, imported it from a `.npy`, and it printed the shim
note, ran correctly, and was refused by `--no-shims`:

    note: probe6 -> mimic_probe6 (shim, subset)
    shim-answered / False

The reason: the shim mapping resolves by recursing through `ParseUsesUnit('mimic_'
+ lo)`, and that re-entry hits the `.py` library-root probe
(`feature-nilpy-import-a-py-module-from-the-library-path`). `isNilPy` is
compilation-wide, so the recursion stays on the Python path. So "the slot is
Pascal-only" was true of ONE question, not of loading.

### The actual defect

`PyMimicShimExists` is asked exactly one thing — *may a host C header win this
name?* — and it probed only `.pas`. So a `.py` shim was invisible **to that
question alone**: fine for a plain name, but any name that also names a host
header lost to the header, and the failure surfaced far away as `undefined
variable` on the first attribute touched. Reproduced with a header-colliding
name (`/usr/include/search.h` exists):

    import search  ->  error: undefined variable (find)

### …and a second, pre-existing bug in the same function

Fixing the extension alone did **not** fix it, which is what exposed the rest:
`PyMimicShimExists` hard-coded CWD-relative `lib/rtl/` and `lib/pcl/` while the
loader is ExeDir-anchored. Run the compiler from any directory but the repo root
and the check answered "no shim" about a shim that then loaded fine. That bug
was **already there for `.pas` shims** — `import string` from another CWD lost
`mimic_string.pas` to `/usr/include/string.h`. Same class again for `-Fu` roots:
the loader probes `PasUnitDirs` for `mimic_<name>.py`, the check did not.

Three spellings of one question, two of them wrong — the
`normalise-dont-special-case` smell exactly. Rewritten as one root × all
extensions helper (`PyMimicShimAt`) applied over every root the loader itself
uses: `-Fu` roots, the ExeDir-anchored lib roots, then the CWD-relative fallback
the stable binary needs.

### Verified

- `.py` shim under a header-colliding name resolves and runs, from inside and
  outside the repo root;
- `--no-shims` refuses it (the observable that proves it is visible AS a shim,
  not masquerading as a library module);
- no regression: `import sqlite3` still reaches the host header (nothing ships a
  `mimic_sqlite3`) — `3045001`; `import string` still reaches `mimic_string.pas`.

Test: `test/test_nilpy_shim_py.npy` + fixture `test/shims/mimic_search.py`,
enumerated in `test-nilpy` (both halves — load AND the `--no-shims` refusal).
Self-contained via `-Fu` so it adds no permanent fixture to `lib/**` (Track B's
file-lane).

**Neither ruling was touched:** no file in the tree carries an upstream name
(the fixture is `mimic_search.py`), and `--no-shims` was not hardened — it
refuses the `.py` shim through the existing mapping branch, unchanged.

### Handoff

This unblocks the `six` half of `feature-nilpy-six-and-warnings-shims` (frank3,
Track B): the slot now accepts `lib/rtl/mimic_six.py`. Shim CONTENT stays that
ticket's — this one only made the slot able to hold it.

Note for whoever takes it: this is the third Track A ticket filed 2026-08-17 with
no Track A worker staffed (with `bug-a-a-python-module-s-identity-is-its-name-not-
its-file` and `bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-
cert`).

## Log
- 2026-08-17 — resolved, commit 42ab5131e.
