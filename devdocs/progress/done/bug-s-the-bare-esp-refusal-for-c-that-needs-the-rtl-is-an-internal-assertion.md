---
slug: bug-s-the-bare-esp-refusal-for-c-that-needs-the-rtl-is-an-internal-assertion
track: S
type: bug
prio: 15
status: done
owner: frank
created: 2026-09-23
resolved: 2026-09-24
commit: PENDING-COMMIT
blocked-by: []
summary: "FIXED 2026-09-24. The bare ESP profile correctly pulls no default RTL, and it said so as an INTERNAL ASSERTION naming a compiler-private symbol -- `compiler error: PXXMemZero not found (xtensa)` for `#include <stdio.h>` plus a printf, on both ISAs -- i.e. a deliberate exclusion reported in the vocabulary this tree reserves for compiler defects, with no action in it. Now a refusal that names the profile and gives two actions (build for IDF, or keep the unit freestanding), raised from ONE place: FindHeapHelperOrRefuse in symtab.inc, which fifteen codegen sites across six backends plus symtab now route through. THE BRANCH IS THE FIX, NOT THE WORDING -- where NoDefaultRtl or TargetIsEspClass holds the absence is a decision and the user gets a refusal; where neither holds, builtinheap should be present and its absence IS an internal fault, so that arm keeps `compiler error:` unchanged. Softening both would have destroyed a real signal. THIS TICKET`S PROPOSED LOCATION DOES NOT WORK AND THE REASON IS RECORDED: the cPullsBuiltinHeap gate knows the POLICY but cannot know the DEMAND -- the pull is decided once at parse time from tokens while a memzero is needed at CODEGEN, with no token signalling it (unlike the softfloat pull beside it, whose demand really is a float token) -- so a refusal there would be unconditional and would break FREESTANDING bare C, which is the supported shape. Deliberately does NOT advise `uses builtinheap`: checked, not assumed -- that does not compile on bare by design (feature-bare-esp-supports-uses-builtin). Controls: freestanding bare C still builds on both ISAs (new fixture), IDF still builds, bare Pascal still builds, x86-64 unaffected. The pre-existing bare row survived because it greps the SYMBOL not the wording, and was NOT sufficient -- asserting only that bare refuses was satisfied by the bad message too, so two rows now pin the message and both were verified to fail against the old one. NOT CONTROLLED, said plainly: the `compiler error:` arm has no positive control because builtinheap absent with no policy is not constructible."
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

---

# FIXED 2026-09-24 (frank)

## The ticket's proposed location does not work, and the reason is worth keeping

This ticket says to raise the refusal beside `cPullsBuiltinHeap` in
`cparser.inc`, *"which already knows both that the profile excludes the RTL and
that this translation unit reaches for it"*. **The second half of that is
false.** That gate knows the POLICY and cannot know the DEMAND:

- the pull is decided **once, at parse time, from tokens**;
- the need for a memzero is discovered at **codegen**, when an aggregate or a
  managed-record temp has to be zeroed;
- **no token signals it.** That is the difference from the softfloat pull a few
  lines below in the same function, which looks like a precedent and is not: its
  demand really is a `float`/`double`/`tkCDouble` token, so a scan can find it.

A refusal at that gate would therefore have to be **unconditional on the bare
profile**, and that breaks **freestanding bare C** — the supported shape, and the
thing `--esp-profile=bare` exists for. So the proposed fix would have traded a
bad message for a broken contract.

## Where it went instead

`FindHeapHelperOrRefuse` in `symtab.inc`, immediately after `FindProc`. **Fifteen
codegen sites across six backends plus symtab now route through it** instead of
each spelling `if procIdx < 0 then Error('compiler error: PXXMemZero not found
(<arch>)')`. That is the one place demand is known, and the ticket's real
complaint — *fifteen sites each discovering a missing symbol* — is answered by
having one of them rather than by moving the question somewhere it cannot be
asked.

**THE BRANCH IS THE FIX, NOT THE WORDING.** Where `NoDefaultRtl` or
`TargetIsEspClass` holds, the absence is a decision someone took, and the reader
gets a refusal naming the profile and two actions. Where neither holds,
builtinheap *should* be there and its absence really is an internal fault — so
that arm keeps `compiler error:` **exactly as it was**. Softening both into one
friendly message would have destroyed a real signal, which is the trap in a
"make the message nicer" ticket.

## Before and after, bare ESP, both ISAs

```
- pascal26:11: error: compiler error: PXXMemZero not found (xtensa)
+ pascal26:11: error: PXXMemZero is provided by the builtinheap unit, and this
+ build excludes the default RTL ... Either build it for the ESP-IDF profile
+ (drop --esp-profile=bare), where the RTL is pulled and crtl is reachable, or
+ keep the unit freestanding and do not call into crtl (in C, that means no
+ <stdio.h>/<stdlib.h> calls such as printf or malloc). Adding a `uses` of the
+ builtin unit is NOT an option on a bare ESP boot today.
```

**It deliberately does NOT advise `uses builtinheap`, and that was checked rather
than assumed:** `uses builtin;` on a bare ESP boot does not compile, by design —
22 arms of `needsBuiltin` carry `(not TargetIsEspClass)`, and
[[feature-bare-esp-supports-uses-builtin]] is open precisely because making it
work is an open-ended sequence of judgement calls, measured four steps deep. The
obvious advice would have sent the reader into that.

## Controls

| | result |
| --- | --- |
| bare ESP + C needing crtl, xtensa AND riscv32 | **refused**, actionable message |
| **freestanding bare C**, xtensa AND riscv32 | **builds** — the row an unconditional gate refusal would have broken |
| IDF profile + C needing crtl, both ISAs | still **builds** (the parent's contract) |
| bare **Pascal**, both ISAs | still builds (the 24 `TargetIsEspClass` sites) |
| x86-64 C, `--emit-obj` and exe | builds; exe prints `hello` |

**The pre-existing bare row survived the rewrite because it greps the SYMBOL, not
the wording** — which is what its own comment said it was for. But it was not
sufficient: asserting only that bare REFUSES was satisfied by the bad message
too. Two rows now pin the message itself — it must name `esp-profile=bare`, and
it must NOT contain `compiler error:` — and **both were verified to FAIL against
the old wording**, so they discriminate rather than decorate.

`test/c_freestanding_on_bare_esp_needs_no_rtl.c` is new and carries the reason it
must stay freestanding, so nobody turns the control into the other test by adding
a printf.

**Not controlled:** the `compiler error:` arm has no positive control, because
reaching it needs builtinheap absent with no policy explaining it, which is not
constructible without breaking the tree. It is the unchanged pre-existing
behaviour, not new code, but it is untested and this says so rather than implying
otherwise.

`make test-emit-obj` GREEN, `gate.sh quick` GREEN, fixedpoint converged.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
