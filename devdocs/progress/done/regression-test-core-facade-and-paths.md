---
prio: 70
---

# regression: test-core#src:examples/tk/facade_and_paths.npy red at d64a5d6a97b4 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-28T14:30:38Z
- **Test source:** examples/tk/facade_and_paths.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:examples/tk/facade_and_paths.npy'` at d64a5d6a97b4484e3d5aefa0b475ab3817d11121

## Range
bad `d64a5d6a97b4`, last good `ebc63e8eafdc`, 6 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-683882/test_nilpy_facade_paths26  [code=1015424B  data=46544B  bss=24876B  procs=1157]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (Track T face-2, 2026-07-28) — root cause is d64a5d6a itself, landed RED

The 6-commit range has exactly ONE code commit: **d64a5d6a**
`feat(pcl,nilpy): ttk widgets, tk constants, and three name-resolution fixes`.
That same commit **modified the failing test** (`examples/tk/facade_and_paths.npy`
+16) **and** its library (`lib/pcl/tkinter.pas` +181). So this is not a
regression a later change introduced into working code — the feature commit
added the test and landed it red.

**Failure mode:** compiles cleanly (`ok: …/test_nilpy_facade_paths26 [code=…]`)
then the RUN fails the expected-output check — NOT a compile error and NOT a
harness `Terminated`. So the compiled façade produces wrong/missing output for
one of the newly added constructs (the commit lists ttk.PanedWindow, Menu with
callable `command=`, Text, `winfo_toplevel`/`title`, and the `tk.CENTER`
name-resolution fix — a good place to start bisecting WHICH one).

Sibling `examples/tk/tkinter_facade.npy` PASSES, so the tkinter façade mostly
works; only `facade_and_paths.npy`'s additions fail.

**Owning lane: Track B** (`lib/pcl/tkinter.pas` + the example is E/B
file-ownership) — the d64a5d6a author. Persistent (in open_regressions, jobs map
= fail), reproduces with the repro line above. T files/enriches, does not fix.
- 2026-07-28 — resolved, commit HEAD.

## Resolution

No longer reproduces. Verified 2026-07-28 three ways at 287b1b34d:

- the program's output is byte-identical to CPython's;
- the watcher's own job passes on the exact repro line —
  `tools/testmgr.py --tier native --job 'test-core#src:examples/tk/facade_and_paths.npy'`
  → GREEN;
- Track T's current state (`tstate/borg.json`) already records this job as
  `pass`.

The stub was signal-only and the underlying red was fixed by the NilPy work in
the range it named. Resolved rather than left ranked at p70, where it was
crowding real work off the top of the queue.
