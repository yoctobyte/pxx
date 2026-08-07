---
track: N
prio: 40
type: bug
summary: "uforth.py now COMPILES (both compile blockers cleared 2026-08-07) but the produced binary segfaults immediately, so `make test-uforth` is still red — now at run time instead of compile time"
---

# uforth compiles and then segfaults

New frontier, not a regression: uforth.py had **never** compiled before
2026-08-07. Two blockers were cleared that day —
[[bug-nilpy-to-bytes-on-a-variant-receiver-does-not-compile]] (line 411) and
[[bug-nilpy-input-builtin-is-shadowed-by-pascals-standard-input-file]]
(line 3352) — and the compile now succeeds:

```
ok: /tmp/uf.bin  [code=4048168B  data=57304B  bss=9580B  procs=1500]
```

`make test-uforth` then fails with `Segmentation fault` (exit 139) at the smoke
step. There is no earlier state to compare against, so nothing here is
attributable to those fixes beyond having made the code reachable.

## Why it matters beyond the corpus

`make test-uforth` is named as the corpus check in
[[bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position]] — *"uforth
still green"* — and that gate has been unreadable for as long as uforth did not
compile. It is still unreadable until this is fixed, which is worth knowing
before anyone plans work that depends on it.

## Where to start

~4300 lines with a layered `.UFO` stdlib, so bisect the RUN, not the source:
`-dPXX_HEAP_DEBUG` first (this session fixed the `--threadsafe` +
`-dPXX_HEAP_DEBUG` deadlock, so both are available together now), then
`-dPXX_OBJTRACE` if it looks like reclamation. uforth exercises the shapes this
session found bugs in — bound-method values, `Callable` fields, escaping
closures, variant receivers — so re-read the day's `done/` tickets before
assuming a new cause.

Watch the measurement traps: `/proc/<pid>/comm` before believing a sample
(a backgrounded `cd X && ./p &` gives the SUBSHELL's pid), and disassemble from
the live process rather than computing file offsets.

## Gate

`make test-uforth` green (uforth.py compiles, STD.UFO loads, the smoke script
runs), plus the ordinary per-fix loop.
