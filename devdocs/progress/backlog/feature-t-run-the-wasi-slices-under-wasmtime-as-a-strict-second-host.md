---
slug: feature-t-run-the-wasi-slices-under-wasmtime-as-a-strict-second-host
title: "Run the four WASI slices under wasmtime too — node cannot see a whole class of bug"
track: A
prio: 25
type: feature
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm (after the u64-alignment bug passed every existing check)
summary: "Every check in test/wasm/ runs its module under node's WASI, which does not enforce the pointer alignment WASI preview1 requires of u64 out-params. Measured: with that defect reinstated, the align slice prints every expected line under node and exits 0, and traps under wasmtime before its first line. check_align.sh now covers the specific calls, but the four general WASI slices — sysio, loadfile, pal, wasi — still run under the lenient host only, so the class stays invisible wherever they are the coverage."
---

> **Re-priced by the owner, 2026-08-30: WASM IS LOW PRIO FROM NOW ON.** *"it works,
> it tests our IR, we should be able to compile applications.. for now, that's good
> enough."* The anchor is met — `pascal26` runs under wasmtime and emits an ELF
> byte-identical to the native compiler's for the same source. wasm has served its
> real purpose, which was exercising the IR from a second direction. These tickets
> stay OPEN and correct; they simply must not outrank ordinary Track A work. Pick
> them up on request, or when a lane is warm on the files anyway.

# The gap

`check_align.sh` (added with
`bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse`) is the
only check that uses a strict host. The four WASI-hosted slices —
`check_sysio.sh`, `check_loadfile.sh`, `check_pal.sh`, `check_wasi.sh` — run
under `node --no-warnings wasihost.js` and nothing else.

That is not a hypothetical blind spot. It is measured: the u64-alignment defect
passed all four, plus every other check, and was caught only by running
`compiler.pas` itself under wasmtime. Under node the unfixed module produces
**correct output and exit 0**.

# The work

For each of the four, run the module a second time under wasmtime against the
same sandbox and diff against the same native oracle. The sandbox construction
already exists in each script; this adds a second runner, not a second setup.

`check_align.sh` has the pattern, including the two things worth copying:

* **wasmtime absent is a loud SKIP**, stating that the box asserted nothing —
  not a silent pass. It is newly installed here and will not be everywhere,
  Track T's watcher clone included.
* **Keep the node run.** It is not redundant: it is what stops a fix made for
  the strict host from quietly breaking the lenient one, and node is what every
  other slice uses.

# The trap to avoid, learned the hard way

Do not assert host-INVARIANT properties that are actually host-DEPENDENT.
`align_slice.pas`'s first version asserted `PalMonotonicMillis > 0`; wasmtime's
monotonic clock starts near zero at process start and node's does not, so a
correct program read 0 on one host and not the other, and the check failed on
correct code the first time it met the second host. A second host turns every
such assumption into a failure, which is the point of adding one — but it means
the diff must be over things both hosts genuinely promise.
