---
slug: bug-s-the-bare-esp-refusal-for-c-that-needs-the-rtl-is-an-internal-assertion
track: S
type: bug
prio: 15
status: backlog
owner: ""
created: 2026-09-23
blocked-by: []
summary: "The bare ESP profile correctly pulls no default RTL, so C that needs a builtin cannot build there -- but it says so as an INTERNAL ASSERTION naming a compiler-private symbol: `pascal26:11: error: compiler error: PXXMemZero not found (xtensa)` for `#include <stdio.h>` plus a printf under --esp-profile=bare, on both ISAs. THE CONTRACT IS RIGHT AND ONLY THE MESSAGE IS WRONG: the Pascal driver has the same situation and answers it with a diagnostic naming a `uses` clause to add, which C has no equivalent of -- so a C programmer gets a symbol they did not write, a `compiler error:` prefix that reads as a compiler defect rather than a refusal, and no action. Deliberately NOT to be fixed by defining PXXMemZero anywhere (see the parent): the symbol exists, the unit is intentionally absent. The remedy is a refusal raised where the POLICY lives, naming the profile and what it excludes, instead of fifteen codegen sites discovering it. Residual of bug-s-c-on-the-esp-profile-cannot-reach-crtl, whose IDF half is fixed."
---

# The bare-ESP refusal for C that needs the RTL is an internal assertion

Split out of [[bug-s-c-on-the-esp-profile-cannot-reach-crtl]] on 2026-09-23,
whose IDF half is fixed. **This half is not a contract bug.** Bare metal getting
no default RTL is the design, and `test-emit-obj` now carries a negative-control
row that pins it.

## What a user sees

```
$ pascal26 --target=xtensa --esp-profile=bare --emit-obj hello.c hello.o
pascal26:11: error: compiler error: PXXMemZero not found (xtensa)
  near: >>>   malloc
```

Line 11 is inside `stdio.h`. `PXXMemZero` is a compiler-private heap helper the
user never wrote and cannot reference. `compiler error:` is the spelling this
tree uses for **internal** faults, so the message reads as "the compiler is
broken" when the truth is "this profile excludes the unit that provides it".

## Why the obvious remedies are both wrong

- **Defining `PXXMemZero` for bare** — refused by the parent ticket, and
  rightly: the symbol is not missing. Doing that fixes one name and leaves
  every other builtin in the same unit just as absent, each surfacing later as
  an unrelated-looking bug.
- **Pulling builtinheap on bare** — that is the widening the parent's fix was
  careful not to do. It would drag the RTL into bare-metal images, which is the
  whole thing the profile exists to avoid.

## The shape of a fix

Raise the refusal **where the policy is decided** — beside
`cPullsBuiltinHeap` in `cparser.inc`, which already knows both that the profile
excludes the RTL and that this translation unit reaches for it — rather than
letting fifteen `ir_codegen_*` sites each discover a missing symbol. The message
should name the profile and what it excludes, and say that freestanding C is the
supported shape here.

The Pascal driver answers the same situation by naming a `uses` clause. **C has
no `uses`**, so the C wording cannot be borrowed and has to say something a C
programmer can act on: use the IDF profile, or do not call into crtl.

## Ranking

Low, and lower after the owner's 2026-09-23 ruling that **IDF is the assumed
profile and bare is a test vehicle** for niche cases. It costs a confusing hour
to whoever meets it on bare and nothing to anyone else. It is a diagnostic-only
change, so it carries no risk to the contract the parent's control row pins.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
