---
slug: bug-a-the-tkinter-demo-hits-a-different-backend-gap-on-i386-and-on-arm32
track: A
prio: 40
type: bug
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "examples/tk/uses_tkinter_and_configparser builds on x86-64 and on no cross target, and the failures are not one cause. ONE REMAINS: i386 'symbol kind not supported yet (load)'. The aarch64 and arm32 ones are both FIXED, and each turned out to be a defect with reach far beyond this demo. riscv32 and xtensa refuse dynamic symbols deliberately (the demo needs libtcl at runtime), so those two are not part of this ticket."
---

# One program, three backend gaps

From the cross attempt (`umbrella-cross-target-codegen-is-correct`, 2026-09-02):

```
uses_tkinter_and_configparser | i386:BUILD arm32:BUILD riscv32:BUILD aarch64:BUILD xtensa:BUILD
```

Five refusals, and reading them is the whole finding — they are **not** one
cause wearing five hats:

| target | message |
| --- | --- |
| i386 | `pascal26:5563: target i386: symbol kind not supported yet (load)` |
| arm32 | `pascal26:2345: target arm32: constructor with more than 4 parameter words not supported` — FIXED, see below |
| aarch64 | `pascal26:399: target aarch64: call argument count mismatch` |
| riscv32 | `target riscv32: external (dynamic) symbols are not supported on this target (first one: Tcl_FindExecutable)` |
| xtensa | same as riscv32 |

## The two that are not defects

riscv32 and xtensa say the true thing: they emit no dynamic segment, and this
demo needs `libtcl` at runtime. That refusal names its own reason and its own
alternatives. **Out of scope here** — it is a target capability, not a gap in
this program's lowering.

## The one to look at first — done, and it was a defect

**aarch64's `call argument count mismatch`** was the odd one out: the other two
name a feature nobody has written, this one named an internal disagreement. A
refusal that reports a count mismatch describes a state the compiler believes is
impossible, so it was a defect until shown otherwise.

It was. Fixed 2026-09-02 —
`bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity`.
aarch64 builds the demo now. The reading was worth more than the ranking: the
same defect was silently writing an EMPTY FILE on x86-64, where no guard
caught it.

## Rank

Low against the other cross work because the program is a binding demo rather
than a core one — but it is the ONLY example in the tree that fails on every
cross target, so it names gaps nothing else reaches.


## 2026-09-02 — arm32 fixed too, and it was worth more than the demo

The arm32 refusal was honest but the ground under it was not. Lifting it needed
a test, the test was written to cover the BOUNDARY rather than the reported
failure, and one row with an `Int64` first parameter — so that the word count
and the argument count stop being the same number — found that **every 32-bit
backend's constructor arm pushed one word per argument**. i386 segfaulted on it,
xtensa answered wrong values, riscv32 had its own arity refusal on top.
`bug-a-the-constructor-argument-ladder-is-the-copy-that-never-learned-argument-classes`.

So of this demo's four causes, two were unwritten features and two were
defects, and both defects reached far outside it. **The remaining i386 one
(`symbol kind not supported yet (load)`) is the last, and on that record it
deserves opening rather than ranking.**
