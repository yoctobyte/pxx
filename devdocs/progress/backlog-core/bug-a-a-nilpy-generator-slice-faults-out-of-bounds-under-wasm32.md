---
slug: bug-a-a-nilpy-generator-slice-faults-out-of-bounds-under-wasm32
title: "`check_nilpy_generator_slot.sh` faults `memory access out of bounds` under wasm32"
track: A
prio: 45
type: bug
status: backlog
created: 2026-09-22
owner: ""
summary: "test/wasm/check_nilpy_generator_slot.sh is RED at HEAD and has nothing to do with --dce: the slice traps `RuntimeError: memory access out of bounds` in the wasm runtime rather than printing its two lines. ESTABLISHED PRE-EXISTING BY STASH-AND-REBUILD, not by reasoning: stashed an unrelated wasm change, rebuilt to `converged after 1 round(s)`, and the check fails identically -- so it is not the wasm32 --dce work landing beside it. The check was written for a WRONG-VALUE defect (`4 2` against `4 5`) and now dies before printing anything, so whatever it originally caught is masked by a fault that arrived later; its own header records the value defect and no longer describes what happens. Found while running the wasm suite for an unrelated change, which is the only reason anyone looked -- check_all.sh reports `at least one check FAILED` and exits 0, so nothing upstream reddens on it."
---

# What

At HEAD (`319ccdade` plus an unrelated local wasm change, and equally with that
change stashed):

```
$ sh test/wasm/check_nilpy_generator_slot.sh
...
RuntimeError: memory access out of bounds
    at wasm://wasm/0076d1ca:wasm-function[1213]:0xcb8d7
    at wasm://wasm/0076d1ca:wasm-function[1918]:0x1c4e11
    at wasm://wasm/0076d1ca:wasm-function[1925]:0x1c542e
    at wasm://wasm/0076d1ca:wasm-function[1926]:0x1c57af
FAIL the slice exited nonzero under wasm:
```

The native leg is fine; the wasm leg traps. `wasm-validate` passes, so this is
a runtime fault and not a malformed module.

# Why it is worth a ticket rather than a fix-on-the-fly

I did not fix it because it is not my topic and diagnosing it properly means
reading the generator lowering, which is a different subsystem from the one I
was in. Banked rather than microfixed.

# What was established, and what was NOT

**ESTABLISHED — it is pre-existing.** Not inferred from "my change was
`--dce`-only". Stashed the unrelated change, rebuilt (`converged after 1
round(s)`, so a real recompute and not the stamp path), re-ran: identical
failure. Restored and rebuilt.

**NOT established:** how long it has been red, or what introduced it. The
pinned compiler is from 2026-08-27 and its output for this slice already
differs from HEAD's, which says only that many commits have landed — it is not
evidence about this fault either way, and I did not bisect.

# The part that matters more than the fault

**The check was written for a WRONG VALUE and now dies before producing one.**
Its own header says so:

> *wasm32 printed `4 2` against x86-64's `4 5` at 0426b285ba35: `t` released at
> the yield, generator resumes holding a one-character string, no crash and no
> diagnostic.*

So a check whose entire point was that the defect is **silent** now fails
loudly for a different reason, and the silent defect it guards is no longer
being tested at all — a trap short-circuits every assertion below it. Whoever
takes this needs to answer two questions and not one: what causes the fault,
and *is the original `4 5` row still green underneath it*. Fixing only the
fault would restore a green check that may have stopped measuring its subject.

# And the suite does not redden on it

`test/wasm/check_all.sh` prints `wasm: at least one check FAILED` and **exits
0**. That is why a red in this directory can sit: the verdict is in the text
and nothing reads it. This is the wrapper-versus-job distinction CLAUDE.md
states for backgrounded jobs, arriving in a test runner — the runner's exit
status is not the run's verdict.

Two failures were present when this was found. The other,
`check_forwards.sh`, was mine and is fixed
(`tools/forwardlint.py` is scope-free and flagged a nested routine named
`Mark` against a local variable named `mark` 38k lines earlier); see
[[bug-t-forwardlint-has-no-notion-of-nested-scope]].

# Where to look first

The trace bottoms out in `wasm-function[1213]`, four frames below the entry, so
it is reached through the generator resume path rather than at startup. The
fixture is `test/wasm/generator_slot_slice.npy` and the lowering under
suspicion is `WasmEmitManagedLocals`' skip predicate, which the check's header
names as the thing it was built to pin — a predicate that skips too much
produces a released slot (the original `4 2`), and one that skips too little
could leave a slot addressed past its frame, which is the shape of an
out-of-bounds. That is a hypothesis from the header, not a measurement; treat
it as the first thing to disprove.
