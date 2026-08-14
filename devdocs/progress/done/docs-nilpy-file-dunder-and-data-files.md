---
track: D
prio: 45
type: docs
blocked-by: [feature-nilpy-file-dunder-from-the-executable]
summary: "User-facing docs for `__file__` / `sys.executable` in a compiled NilPy program: they name the EXECUTABLE, not the source, so `dirname(abspath(__file__))` is the binary's directory. Ship data files next to the binary. Blocked until the implementation lands so the docs describe what ships, not what was decided."
status: done
owner: claude-D
---

# Document `__file__` and where a NilPy program's data files live

- **Type:** docs (user-facing) — **Track D** (`docs/**`)
- **Opened:** 2026-08-13, alongside
  [[decide-nilpy-dunder-file-for-a-compiled-program]] (the decision and its
  reasoning) and [[feature-nilpy-file-dunder-from-the-executable]] (the
  implementation).
- **Blocked-by the implementation on purpose:** today `__file__` is an
  unresolved `argv[0]` and `sys.executable` does not exist, so documenting the
  decided behaviour now would describe something that does not ship yet.

## What to write, and where

The NilPy target page (`docs/targets/nil-python.md`) is the home; it already
carries the "what differs from CPython" material a reader needs this next to.

The one paragraph that matters to a user:

> A compiled NilPy program has no source file at run time, so `__file__` names
> the **executable**: for the main module it is the binary's own path, and for an
> imported module it is that binary's directory plus the module's file name — a
> path that need not exist. `sys.executable` is the same binary. This means
> `os.path.dirname(os.path.abspath(__file__))` — the usual way to find data
> files that ship with a program — resolves to **the directory the executable is
> in**. Put your data files next to the binary.

Then the two consequences, stated plainly rather than buried:

- `open(__file__)` works for the main module and fails for an imported one.
- Code that ships data beside its `.py` sources and relies on `__file__` to find
  it must either move the data next to the binary or be given the path another
  way. Worth showing the shape, because it is what a reader will hit:

  ```python
  here = os.path.dirname(os.path.abspath(__file__))   # the executable's dir
  path = os.path.join(here, "data.json")
  ```

## Tone: this is a property, not an apology

Frozen Python (PyInstaller, cx_Freeze) makes the same choice for the same
reason, and it is worth one sentence saying so — a reader who has shipped a
frozen app already knows this shape. Do not present it as a limitation; present
it as "here is where a compiled program's data lives".

Do **not** document `--data-root`: it is deliberately unbuilt (see the decision
ticket). If it lands later, this page is where it goes.

## Cross-references to keep in step

If the behaviour is ever revisited — a new use case, a change of mind — these
four must move together:

- `decide-nilpy-dunder-file-for-a-compiled-program` (the decision + rejected options)
- `feature-nilpy-file-dunder-from-the-executable` (the implementation)
- `devdocs/dev/nilpy-semantics-divergences.md` (the internal divergence entry)
- this ticket / `docs/targets/nil-python.md` (the user-facing text)

## Gate

Docs internally consistent; every snippet compiled against `$(PXX_STABLE)` and
its printed output checked, **running the binary from a different directory than
it was compiled in** — otherwise the example demonstrates nothing (the CWD and
the source directory coincide, which is exactly the blind spot that hid this bug
until 2026-08-13).

## Log
- 2026-08-14 — done. New section "`__file__`, `sys.executable`, and where data
  files live" in `docs/targets/nil-python.md`, placed BEFORE "Known gotchas"
  deliberately: per the ticket's tone note this is a property of compiled
  programs, not a defect, and the gotchas list is where readers go looking for
  defects. Frozen-Python parity gets its one sentence.
  Measured against pinned v303, and — per the gate — with the binary **copied to
  a different directory and run from a third one**, which is the check the blind
  spot needed: main `__file__` and `sys.executable` both give the relocated
  binary's absolute path, `dirname(abspath(__file__))` follows it, and an
  imported module's `__file__` is that new directory + `mymod.py` (note the
  `.py`, though the source was `.npy`, and nothing is at that path).
  `open(__file__)` verified both ways: the main module opens the ELF itself
  (2,064,127 bytes read) and an imported module's raises. Documented that the
  main-module case *succeeds* rather than leaving it as "works" — a reader who
  tries it gets megabytes of ELF, and that is the surprising half.
  `--data-root` deliberately not mentioned. Internal divergence entry
  (`devdocs/dev/nilpy-semantics-divergences.md:221`) checked as consistent, not
  edited — it is not Track D's file.
- 2026-08-14 — resolved, commit 5692e47fb.
