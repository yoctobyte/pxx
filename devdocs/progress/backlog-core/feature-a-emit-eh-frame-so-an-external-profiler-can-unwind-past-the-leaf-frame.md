---
track: A
prio: 50
type: feature
blocked-by: []
summary: "pxx emits no `.eh_frame` (the string appears nowhere in `compiler/`), so gdb and any sampling profiler can report the LEAF function and nothing above it. Leaf profiling works today via the `.map`; inclusive profiling is unavailable."
---

# Emit .eh_frame so an external profiler can unwind past the leaf frame

`grep -rl eh_frame compiler/` returns NOTHING, and a pxx executable carries no
section headers and `symtab entries: 0`. A tracer can therefore read the current
PC and no caller chain: **the leaf frame is measurable, everything above it is
best-effort at best.**

Raised 2026-09-15 by the lekkerzeilen seat while building a sampling profiler to
answer "what costs 4.9 ms in one `Vessel.step`" — a question an evening of
editing-and-inferring failed to answer and that a profile answers directly. They
can report a leaf profile as measured and must label anything deeper as
suggestive. That is the concrete cost and it is the whole ticket.

## What already works, and it is more than it looks

**pxx writes `<output>.map` beside EVERY executable** — no flag, no `-g`, no
rebuild. `# Frankonpiler Map File`, `# Base Address: 0x00400000`, then
`0xADDR Name` per proc (verified 2026-09-15: a trivial two-class NilPy program
emits a 60 KB map; lekkerzeilen's is 4256 lines). The binary is **non-PIE**, so
there is no load slide to correct and PC -> name is a sorted lookup against the
file as written.

**So leaf profiling needs nothing from this ticket**, and it works on binaries
built hours ago without recompiling them — which is the property that matters,
because a rebuilt binary is not the binary whose number you are explaining.
`-g` (DWARF line info) exists too and `--doctor` confirms gdb, but a `-g` build
is a DIFFERENT binary from the one measured, so using its profile for the other
one's timings requires proving the text bytes identical first. The map has no
such caveat.

**This is undocumented as a profiling instrument.** The `.map` is mentioned in
`debugging-playbook.md`, `debug-switches.md` and `valgrind.md`, but nowhere in
connection with profiling, symbolisation or address lookup — grep confirms zero
hits. A seat with full repo access went looking for a way to profile and found
it only by inspecting a build directory. **Documenting it is worth more, sooner,
than implementing this ticket**, and is not blocked by it.

## Scope note — do NOT widen this to exceptions without measuring

pxx has working exceptions and this ticket does NOT claim they are affected;
whatever unwinding they use does not go through `.eh_frame`, since there is none.
The claim here is narrow and measured: **EXTERNAL tools cannot unwind.** Anyone
picking this up should establish the interop question (C++ unwinding across a pxx
frame, for instance) separately rather than inheriting it from this summary.

## Host caveat that belongs with any profiling instruction

`/proc/sys/kernel/yama/ptrace_scope` is **1** on plexus, so a tracer must be an
ancestor of its target: **gdb cannot ATTACH to a running demo** and must LAUNCH
it (`run &`, then `interrupt`/`continue &` driven down a fifo). Any doc that says
"attach and sample" is wrong on this host — the attach is what fails, not the
sampling. gdb also disables ASLR by default, which is harmless for a profile but
is the same switch behind the `setarch -R` rule, so a fault that only occurs
under ASLR will not appear in such samples.
