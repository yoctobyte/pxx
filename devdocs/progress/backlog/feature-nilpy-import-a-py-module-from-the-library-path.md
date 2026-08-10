---
track: A
prio: 55
type: feature
summary: "A NilPy `import X` finds X.py only as a SIBLING of the importing file; the fall-through chain looks for units (.pas) only, so a .py module shipped in lib/** is unreachable. Blocks shipping any NilPy-written library, starting with tkhtmlview"
---

# a `.py` module shipped in `lib/**` cannot be imported

- **Type:** feature (NilPy module resolution) — **Track A** file ownership
  (`compiler/parser.inc`, the shared unit-resolution path), Track N facing
- **Opened:** 2026-08-10, sizing [[feature-b-tkhtmlview-in-nilpy]]. Found before
  the port started, which is the point — without this the port would land and
  then not be importable as a library.

## Measured

```
$ cat lib/pcl/zzprobe.py
def hello(): return "from-lib-pcl"

$ cat /tmp/imp/main.py
from zzprobe import hello
print(hello())

$ pascal26 /tmp/imp/main.py /tmp/imp/main
pascal26:1: error: import: no unit named zzprobe and no shim mimic_zzprobe
```

The identical file **as a sibling** of `main.py` works and prints
`from-lib-pcl`. So the module is fine; only its location is unreachable.

## Cause — read off the resolver, not guessed

`compiler/parser.inc`'s NilPy arm tries `.py` then `.npy` in **`CurUnitDir`
only** — the importing file's own directory, which is Python's rule and is
deliberately so (its comment explains that `lib/pcl/tkinter.pas`'s `uses tk`
must not be hijacked by a stray `tk.npy` beside the user's script).

When that misses, the import falls through to the ordinary unit search chain —
which resolves `.pas`. Nothing in the chain ever tries `.py`/`.npy` in a
library root, so `import re` finds `lib/rtl/re.pas` but an `import X` can never
find `lib/**/X.py`.

## Why it matters now

It is the prerequisite for shipping **any** library written in NilPy. The
immediate case is [[feature-b-tkhtmlview-in-nilpy]], which was scoped as "pure
Track B" and is not, purely because of this. Beyond that it is what makes
"NilPy as a library language" real rather than a property of single-directory
programs.

## Shape of the fix

Extend the NilPy arm so that after the sibling probe misses, the search roots
(`-Fu` / `-I` entries and the shipped `lib/**` roots) are each tried for
`<name>.py` then `<name>.npy`, **before** the `.pas` fall-through — or after
it; that ordering is the one real design question:

- **`.py` before `.pas`** lets a NilPy library shadow a same-named Pascal unit,
  which is how a port would replace `tkhtmlview.pas` without touching callers.
- **`.pas` before `.py`** keeps every existing resolution bit-identical and
  makes a port an explicit swap (delete the `.pas`).

Prefer the second unless the first is needed: it cannot change any program that
compiles today, and `bug-nilpy-stdlib-name-binds-pascal-unit` is the record of
how much subtlety lives in this ordering. **Keep the sibling-first rule
untouched either way** — it is Python's own semantics and it is load-bearing
(see the `tk.npy` note in the resolver's comment).

## Gate

The probe above importing from `lib/pcl/`; `make test-nilpy` green (the suite
has multi-module tests that rely on sibling-first — those must not move);
self-host byte-identical; `import re` still reaching `lib/rtl/re.pas`.
