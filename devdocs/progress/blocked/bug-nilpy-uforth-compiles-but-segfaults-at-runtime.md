---
track: N
prio: 40
type: bug
blocked-by: bug-nilpy-pyeval-host-call-refuses-a-mixed-variant-and-scalar-param-shape
summary: "uforth.py compiles, BOOTS, and now compiles colon definitions correctly (segfault + property-setter fixes, 2026-08-08). Still red: blocked on bug-nilpy-pyeval-host-call-refuses-a-mixed-variant-and-scalar-param-shape, hit by the first PYTHON-bodied word that calls back into define_word"
---

# uforth compiles, boots, and stalls loading STD.UFO

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

## 2026-08-08 — the crash MOVED (still red, new location)

[[bug-nilpy-closure-stored-in-a-callable-field-jumps-through-the-variant-tag]]
cleared the tag-jump. `make test-uforth` is still red, at a different place.

- **was:** `uforth.py:841` `word.native(self)`, **PC = 0x0a** — literally
  `VT_BOUNDFN_TAG`, i.e. a variant tag word read as a code address.
- **now:** **PC = 0x4dfce7, inside `pyboundfn_callvn`** (symbolised via the
  `.map`; `readelf` is blind on pxx binaries). A real code address.

It now dies during STARTUP, **before the banner** — so it is a native word run
while loading `STD.UFO`, not line 841's token. (stdout is empty on the crash;
that is buffering, not evidence about where it got to.)

The faulting instruction is the one right after the bridge's indirect call:

```
  lea -0x1f0(%rbp),%rax ; mov %rax,%r10 ; pop %r11 ; call *%r11 ; push %rax
=> mov (%rax),%rcx          <-- rax = 0
```

`pyboundfn_callvn` calls the body through `TBF<n>`, a **Variant-returning**
function type (`rv := f1(p[0])`). uforth's native words are explicitly
`def w_plus(vm: VM) -> None:` — real PROCEDURES, which never set `rax`, so the
result is read from a null pointer. `TBoundFnObj` carries no `IsFunc` field,
where the `pybound_new` path carries exactly that flag for exactly this reason
(bug-nilpy-void-def-assigned-and-called-crashes).

**That hypothesis is NOT confirmed.** The obvious minimal repros of it both
PASS: a `-> None` nested def stored in a dataclass `Callable` field, and the
same reached through a keyword `define_word(name, native=w_plus)` that mirrors
uforth's own shape. Whatever uforth hits needs an ingredient those do not have —
find it before writing a fix, and diff against the CPython oracle rather than
reasoning from the disassembly alone.

## 2026-08-08 (later) — SEGFAULT FIXED. uforth boots and evaluates; now blocked on a different bug

`pyboundfn_callvn` chased to root and fixed. uforth no longer crashes: it prints
its banner, loads part of `STD.UFO`, and `1 2 + .` correctly answers `3`.
`make test-uforth` is STILL RED, on
[[bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver]] —
`blocked-by:` that, nothing left here.

### Root cause

`PyParseDefHeader` normalises a def that is used as a VALUE onto the
function-object ABI (variant result, variant parameters) — but it exempted a
`-> None` PROCEDURE: *"A procedure stays a procedure — there is no result to
disagree about."* There is. Every bridge calls a function value through a
VARIANT-RETURNING pointer type unconditionally — pyeval's `TBF0..TBF13` in
`pyboundfn_callvn`, `pybound_callv*`, and every `Callable[...]` signature, whose
own comment in `PyAnnTypeAt` states it outright: *"a Callable signature is
ALWAYS a variant-returning function."* A real procedure never sets the result
register, so the bridge read the result from whatever was left there and
dereferenced it.

The METHOD arm of the same rule (`PyMethodUsedAsValue` in
`PyRegisterClassMembers`) has always normalised unconditionally, and its comment
records the identical history — *"a value-returning bound method crashed, a
`-> None` one worked, which is why this looked like a receiver bug rather than
an ABI one."* Two arms of one rule that disagreed. The exemption is gone; the
def arm now forces `PyHdrIsProc := False` and a variant result, like the method
arm.

### Why it read as unfixed, and the measurement trap

Reading an unwritten register is UNDEFINED, not reliably fatal, so a
crash/no-crash test of this is BLIND — and both the earlier minimal repros and
the existing regression test `test_nilpy_void_def_value_call.npy` were exactly
that, and passed on the broken build.

The gdb evidence that settled it: only THREE calls reach the bridge before the
crash — `w_include`, `w_backslash`, `w_colon` (r11 at the indirect call,
symbolised through the `.map`). All three are `-> None`. The first two returned
with a mapped address left in the register, so the junk read was harmless; the
third returned 0 and it faulted. Disassembling all three ends confirmed the
compiler emitted `leave; ret` with no result written — i.e. procedures — which
is the fact a pass/fail run cannot give you.

`test_nilpy_void_def_value_call.npy` now PRINTS the result instead of merely
calling, and covers the Callable-field route too: `pinned` prints `0` where
CPython prints `None`, so it is deterministic in both directions.

### uforth's remaining failure

```
: X 1 ; 5 X .     CPython: 1        pxx: 5      (X's body is empty)
.S                CPython: <empty>  pxx: 13 junk entries (CORE.UFO's PYTHON
                                    word bodies, pushed as string literals)
STD.UFO           dies at CORE.UFO:80, "expected a number, got str"
```

One cause, all three: `w_colon`'s `vm.compiling = True` is silently DROPPED
because `compiling` is a `@property` with a setter and `vm` is a dynamically
typed parameter. Every colon definition therefore stays in interpret mode and
its body executes instead of compiling. Filed, with a 25-line repro, as
[[bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver]] —
PRE-EXISTING (reproduced under `pinned`), just unreachable until now.


## 2026-08-08 (third pass) — past STD.UFO's colon definitions, new blocker

[[bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver]] fixed
(three separate silent property-write losses, see that ticket). `vm.compiling =
True` in `w_colon` now takes effect, so colon definitions COMPILE instead of
executing and the junk that was landing on the data stack is gone.

`make test-uforth` now fails in a different component:

```
pyeval: host method define_word has an unsupported param shape
```

pyeval's host-call bridge accepts only an ALL-variant or an ALL-pointer-sized
parameter list, and `define_word(name: str, native: Callable, immediate: bool)`
mixes the two. Filed as
[[bug-nilpy-pyeval-host-call-refuses-a-mixed-variant-and-scalar-param-shape]];
`blocked-by:` moved there. Nothing left in this ticket again.
