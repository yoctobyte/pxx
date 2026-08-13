---
track: U
prio: 55
type: decision
blocked-by: []
summary: "What should __file__ be in a COMPILED NilPy program? Today it is argv[0] (the binary), CPython says the source path. The idiom that cares is `os.path.dirname(os.path.abspath(__file__))` to find data files next to the script — it is how uforth locates STD.UFO, and it fails today when the binary and the sources live in different directories."
---

# Track U: what is `__file__` in a compiled NilPy program?

- **Type:** decision — **Track U**
- **Found:** 2026-08-13, driving the uforth corpus
  ([[feature-nilpy-corpus-uforth]]) from its `tests/` directory instead of from
  the project root.

## The fork

CPython's `__file__` is the path of the **source file** the module was loaded
from. A compiled NilPy program has no module load at run time, so the compiler
has to choose what the name means. Today it answers **`argv[0]`** — the binary:

```python
import os
print(__file__)                                   # pxx: ./ff1     CPython: /path/ff1.npy
print(os.path.dirname(os.path.abspath(__file__))) # pxx: dir of the BINARY
```

Both are defensible. They differ exactly when the binary and the source do not
sit in the same directory, which is the normal case (`pxx src/app.py /tmp/app`).

## Why it matters — this is not a cosmetic divergence

The dominant real-world use of `__file__` is **"find the data files that ship
next to my script"**:

```python
script_dir = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(script_dir, "STD.UFO")
```

That is uforth's own stdlib lookup, verbatim. Run from the project root it
works by accident (the CWD probe hits first); run from `tests/` it prints
`STD LIB NOT FOUND` under pxx and loads fine under CPython, and every
conformance driver then fails with `THROW -13` on the first undefined word. So
the whole Forth-2012 driver set is currently unrunnable from `tests/` on pxx
and runnable on CPython — squarely the "works on CPython must work on NilPy"
rule.

## The options

1. **Bake the SOURCE path at compile time** (absolute, resolved when compiling).
   Matches CPython for the idiom above and for the multi-module case (each
   module gets its own source path). The oddity: ship the binary without the
   sources and `__file__` names a path that no longer exists — which is also
   what CPython does with a deleted `.py`, and it is only a string.
   **Recommended.**
2. **Keep `argv[0]`** (today). Answers "where is the binary", which is useful —
   but `sys.argv[0]` and `sys.executable` already answer that, so the current
   arrangement spends `__file__` on a question that is not asking it, and gets
   the data-file idiom wrong.
3. **Compile-time source path, with a run-time fallback to the binary's
   directory when that path no longer exists.** Most forgiving, but it makes
   `__file__` non-deterministic — the same binary answers differently on two
   machines — and silent fallbacks are what this codebase generally refuses.
4. **A flag** (`--file-dunder=source|argv0`). Cheap, and the wrong shape: it
   turns a semantics question into a per-invocation one, so library code cannot
   rely on either answer.

## Recommendation

Option 1, and let `sys.argv[0]` keep meaning the binary. If a program genuinely
wants "next to the executable", that is a different question with a different
spelling, and NilPy should probably grow `sys.executable` for it (small, Track
N, separate).

Once decided this is ordinary Track N work — the compiler already knows the
source path at parse time — and it re-files into that lane.
