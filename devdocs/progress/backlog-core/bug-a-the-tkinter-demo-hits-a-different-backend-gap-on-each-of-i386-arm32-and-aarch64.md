---
slug: bug-a-the-tkinter-demo-hits-a-different-backend-gap-on-each-of-i386-arm32-and-aarch64
track: A
prio: 40
type: bug
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "examples/tk/uses_tkinter_and_configparser builds on x86-64 and on NO cross target, and the five failures are not one cause: i386 'symbol kind not supported yet (load)', arm32 'constructor with more than 4 parameter words not supported', aarch64 'call argument count mismatch' -- which reads like a defect rather than a refusal and is the one to look at first. riscv32 and xtensa refuse dynamic symbols deliberately (the demo needs libtcl at runtime), so those two are NOT part of this ticket."
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
| arm32 | `pascal26:2345: target arm32: constructor with more than 4 parameter words not supported` |
| aarch64 | `pascal26:399: target aarch64: call argument count mismatch` |
| riscv32 | `target riscv32: external (dynamic) symbols are not supported on this target (first one: Tcl_FindExecutable)` |
| xtensa | same as riscv32 |

## The two that are not defects

riscv32 and xtensa say the true thing: they emit no dynamic segment, and this
demo needs `libtcl` at runtime. That refusal names its own reason and its own
alternatives. **Out of scope here** — it is a target capability, not a gap in
this program's lowering.

## The one to look at first

**aarch64's `call argument count mismatch`** is the odd one out: the other two
name a feature nobody has written, this one names an internal disagreement. A
refusal that reports a count mismatch is describing a state the compiler
believes is impossible, so it is a defect until shown otherwise, and it is
cheaper to reproduce than either of the others.

## Rank

Low against the other cross work because the program is a binding demo rather
than a core one — but it is the ONLY example in the tree that fails on every
cross target, so it names gaps nothing else reaches.
