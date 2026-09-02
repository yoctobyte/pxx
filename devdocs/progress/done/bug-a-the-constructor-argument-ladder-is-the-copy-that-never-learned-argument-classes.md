---
slug: bug-a-the-constructor-argument-ladder-is-the-copy-that-never-learned-argument-classes
track: A
prio: 65
type: bug
status: done
created: 2026-09-02
found: 2026-09-02
found-by: frankC
owner: frankC
commit: PENDING-COMMIT
blocked-by: []
summary: "Every 32-bit backend's class-instantiation arm pushed ONE WORD PER ARGUMENT, so an Int64, Double or 5..8 byte record constructor parameter lost its high word and shifted every parameter after it. i386 SEGFAULTED on all three (the reload of Self read an argument instead of the instance); arm32 and xtensa answered wrong values. arm32 additionally refused any constructor over four parameter words and riscv32 over eight. FIXED on all four: the ctor ladder now asks Arg32Class like the direct, virtual and indirect ones, and the over-the-register-boundary case keeps the overflow on the stack across the call the way those paths already do."
---

# The constructor ladder is the fifth copy, and it asked neither question

## How it was found, which is the part worth repeating

Not by auditing constructors. `examples/tk/uses_tkinter_and_configparser` failed
on arm32 with `constructor with more than 4 parameter words not supported`, so
the repro was a class with six Integer parameters. That fix took ten minutes.

**Then the TEST was written to cover the boundary rather than the failure** —
one word, three, four (the old limit), nine, and then an `Int64` first parameter
*so that the word count and the argument count stop being the same number*. That
last row is the whole finding: a limit expressed in WORDS cannot be tested with
arguments that are all one word each.

It failed on arm32, on xtensa, and crashed on i386 — three defects nobody was
looking for, from one row added on principle.

## What was wrong

Five paths marshal a call on a 32-bit backend: direct, virtual, indirect,
external, and **class instantiation**. The first four ask `Arg32Class`. The
constructor arm pushed one word per argument on all four backends:

| target | before | symptom |
| --- | --- | --- |
| i386 | 4 bytes/arg | **SEGFAULT** on Int64, record and Double alike |
| arm32 | 1 word/arg, and refused > 4 words | `Create(70000,1,2,3,4)` gave 4295039530 for 71234 |
| riscv32 | 1 word/arg, and refused > 8 words | refusal fired first |
| xtensa | 1 word/arg | 8589938036 / 702091 / 700001 for 71234 / 702039 / 702509 |

i386's crash has a mechanism worth stating: the ctor arm reloads Self from
`[esp+argBytes-4]` after the call, and `argBytes` was computed from the same
wrong count — so it read an ARGUMENT as the instance pointer and the caller used
it as one.

## The fix

Each backend's ctor arm now asks `Arg32Class` and advances by `Arg32Words`,
emitting through the ladder that backend already uses elsewhere
(`EmitCallArgWordsRISCV32` is literally the shared helper the other three
riscv32 paths call — the constructor was the fourth caller it never had). On
xtensa the even-word pad (`XtensaPadTo64Xtensa`) comes with it, because the
callee spill runs one shared 64-bit branch for Int64, Double and a 5..8 byte
record and skips an odd word on its side too.

The arity refusals go with them. arm32 over four words and riscv32 over eight now
keep the whole pushed block live across the call — words past the registers ARE
the callee's incoming stack arguments — and reload Self from its slot afterwards
instead of saving a second copy. That is what the direct, virtual and indirect
ladders in those same files already do.

## Verification

`test/test_ctor_arg_classes_and_arity.pas`, rows from one word to nine plus one
row per multi-word class, **passes on all six targets**. Two-directional against
the pinned compiler:

```
x86-64  fails=0 WIDECTOR OK      <- the control that must not change
i386    REFUSED (only ordinal/pointer parameters supported yet)
arm32   REFUSED (more than 4 parameter words)
riscv32 REFUSED (more than 8 parameter words)
xtensa  fails=3 WIDECTOR FAILED
```

No regression in the neighbours: `test_call_arg_marshalling_32bit`'s xtensa
mismatch rows are the same eight as the pinned baseline (its known Int64/Double/
set gaps on the virtual and indirect ladders, deliberately out of scope), and
`test_cross_set_param`, `test_cross_virtual_indirect_aggret`,
`test_arm32_record_byval_wide` and `test_byvalue_record_param_every_call_shape`
are green on all five cross targets.

## What it says about the shape

Fourth instance in two days of the same thing: a decision that exists once as a
shared oracle, and one call path that does not consult it. `Arg32Class` was
extracted for exactly this and the extraction converted four paths, not five.
The next one to check is the EXTERNAL/cdecl arm on each backend.
