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
