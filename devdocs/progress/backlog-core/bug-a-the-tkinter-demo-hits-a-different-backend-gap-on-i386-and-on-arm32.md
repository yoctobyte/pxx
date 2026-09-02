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
summary: "examples/tk/uses_tkinter_and_configparser builds on x86-64 and on no cross target, and the failures are not one cause. TWO REMAIN: i386 'symbol kind not supported yet (load)' and arm32 'constructor with more than 4 parameter words not supported'. The aarch64 one was the defect the reading predicted and is FIXED. riscv32 and xtensa refuse dynamic symbols deliberately (the demo needs libtcl at runtime), so those two are not part of this ticket."
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
