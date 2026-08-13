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

## DECIDED 2026-08-13 (user) — option 2, derived from the executable at RUN time

**`__file__` and `sys.executable` both derive from `argv[0]`.** A per-application
override is wanted but is NOT built until something actually needs it.

### What killed option 1, and it was not the argument this ticket opened with

Baking the compile-time source path **leaks the build environment into the
binary** — the absolute path of the machine that compiled it, present even with
debug info off, in every shipped artifact. That is undesirable on its own terms,
and it is separate from the (already known) problem that the path stops existing
the moment the binary moves. Option 1 is out.

Option 3 (compile-time path, run-time fallback) is out for determinism: the same
binary would answer differently on two machines, and a silent fallback is the
pattern this codebase refuses elsewhere. Option 4 as originally written — a flag
switching the SEMANTICS — is out because library code could then rely on
neither; the choice the programmer actually wants is an application-level data
root, which is a different thing and is recorded below.

### The frame that settles it: pxx is a FREEZER, not an interpreter

The implementations to imitate are PyInstaller / cx_Freeze, not CPython running
source. They answered this same question: `sys.executable` is the binary, and
`__file__` is a path inside a directory the frozen app owns (`sys._MEIPASS`, a
temp mount). They mount only because they must EXTRACT; we do not, so we get
the useful half without the machinery.

### The rule

- Derive from the **resolved** executable path, not raw `argv[0]` — `argv[0]` can
  be a PATH lookup, a relative path, or whatever an `exec` caller passed.
  `/proc/self/exe` on hosted Linux; resolve `argv[0]` against PATH/CWD elsewhere.
- **Main module:** `__file__` = the executable's own path. Truthful, and
  `os.path.exists(__file__)` is True.
- **Imported module:** `__file__` = `<exe_dir>/<original module basename>` —
  a virtual path (nothing is there), deterministic, and leaking nothing.
- `sys.executable` = the same resolved binary path. Adding it takes "where am I
  installed" off `__file__` permanently.

The payoff is that the only form that matters in practice,
`os.path.dirname(os.path.abspath(__file__))`, yields **the executable's
directory** for every module — i.e. exactly where a shipped app's data sits.

### Not a strict win, and the trade should be stated

uforth run from `tests/` finds `STD.UFO` under this rule only if the BINARY sits
beside it (under CPython it works because `uforth.py` genuinely is beside it).
So this trades "works when you ship source" for "works when you ship the binary
next to its data" — the right trade for a compiler, but a trade.

### Deferred until something needs it: the application data root

A `--data-root=<path>` (compile time) and/or a run-time override setting the base
directory those virtual paths hang off, default = the executable's directory.
That serves the packager who installs data in `/usr/share/<app>` WITHOUT making
`__file__` mean two different things to library code. **Not built now** (user):
wait for the first program that needs it.

### Documented divergence, not a defect

`open(__file__)` on an imported module fails — there is no file there. That is
the third-most-common use of `__file__` (after locating siblings and logging),
and frozen Python has the same property once its temp dir is gone. Goes in
`devdocs/dev/nilpy-semantics-divergences.md`.

### Why this took until 2026-08-13 to surface — the blind spot is ours

uforth probes the CWD first and only falls back to `__file__`:

```python
path = "STD.UFO"
if not os.path.exists(path):        # CWD — and it almost always hits
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "STD.UFO")
```

Every earlier run was from the project root, where `STD.UFO` is in the CWD, so
the `__file__` branch never ran. It took a driver (`runtests.fth`) that includes
its siblings by bare name and therefore forces the run to happen from `tests/`.

**Generalise it: our corpus habit hides this whole class.** We compile a program
in its source directory and run it there, so "the CWD" and "where the source
lives" coincide and any `__file__`-based path resolution silently agrees with the
CWD-based one. Any future path-resolution bug of this shape needs a program that
both reaches the fallback and runs from somewhere else.

### Where this decision lives, and what must move with it

Four places, and a change of mind (or a new use case) has to move all four:

- **this ticket** — the decision, the rejected options and why;
- [[feature-nilpy-file-dunder-from-the-executable]] — the implementation;
- `devdocs/dev/nilpy-semantics-divergences.md` — the internal divergence entry,
  under "`__file__` names the EXECUTABLE, not the source";
- [[docs-nilpy-file-dunder-and-data-files]] — the user-facing text (Track D),
  blocked on the implementation so it describes what ships rather than what was
  decided.
