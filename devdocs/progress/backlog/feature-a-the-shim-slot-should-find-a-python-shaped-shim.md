---
slug: feature-a-the-shim-slot-should-find-a-python-shaped-shim
track: A
prio: 70
status: backlog
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

Note for whoever takes it: this is the third Track A ticket filed 2026-08-17 with
no Track A worker staffed (with `bug-a-a-python-module-s-identity-is-its-name-not-
its-file` and `bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-
cert`).
