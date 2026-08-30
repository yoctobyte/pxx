---
slug: feature-a-one-argv-to-frozen-filler-instead-of-x86-64s-inline-copy
track: A
prio: 30
type: feature
status: new
owner: ""
blocked-by: []
summary: "argv -> frozen string is implemented TWICE: five backends call the RTL's PXXCStrToFrozen, and x86-64's EmitArgvToString open-codes the same contract as emitted bytes (its own strlen, its own cmp against FROZEN_CSTR_CAP, its own rep movsb). They agree on 255 today, and the agreement is maintained by hand. Normalising means deleting the inline copy and making x86-64 call what the other five already call -- no observable behaviour change. Filed rather than bundled into the crash fix that measured it."
---

# One argv→frozen filler, not x86-64's inline copy plus everybody else's call

- **Filed:** 2026-08-31 by frankA, out of
  `bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets`, which
  fixed the crash and deliberately left this.
- **Nothing is broken today.** The two copies agree.

## The measurement that changed the shape of this

Its parent ticket predicted a third copy of the *clamp*. Counted rather than
assumed, the clamp is **already shared**: `PXXCStrToFrozen` (`FROZEN_CSTR_CAP`,
nil→`''`) is what i386, arm32, aarch64, riscv32 and xtensa reach on the frozen
path. **One** backend reimplements it — x86-64's `EmitArgvToString`, which emits
its own `repne scasb` strlen, its own `cmp` against the cap and its own
`rep movsb`.

So this is one copy to delete, not three to reconcile, and the direction is
settled by the count: **x86-64 joins the five**, not the other way round.

## Why it is worth doing at all, given nothing is broken

The crash fix that produced this ticket had to be written **five times**, once
per backend, in five different instruction sets — and the reason is that the
bound belongs next to the fill, and the fill lives in the backend. Each of those
five is now correct; a sixth target gets a sixth chance to be wrong, and the
thing it will be wrong about is the part that is *already* common code
everywhere but x86-64.

The observable contract — 255, and `''` for nil — is the same one FPC answers,
so there is a fixed target and nothing to decide.

## Not free, and the cost is the reason this is p30

x86-64 is the hot path for the compiler itself. A call into the RTL where there
is currently a straight-line `rep movsb` is a real change in generated code for
every `ParamStr` in expression position, and `ParamStr` inside a loop over
`ParamCount` is the shape the parent bug was reported from. Measure before
landing; if the call costs anything visible, the answer is to keep one filler
and inline it, not to keep two fillers.

## Gate

`make compiler/pascal26`, plus the rows this ticket's parent wired:
`test_paramstr_out_of_range` and `test_paramstr_long_arg` on all six targets.
Both already fail against a pre-fix binary, so they are guards and not
decoration.

## Related

- `bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets` (the fix, and the count above)
- `bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp` (the parent, which put the clamp into `EmitArgvToString` in the first place)
- `devdocs/dev/normalise-dont-special-case.md`
