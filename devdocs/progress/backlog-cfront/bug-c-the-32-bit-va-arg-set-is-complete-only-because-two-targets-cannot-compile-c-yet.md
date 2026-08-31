---
slug: bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet
track: C
prio: 35
type: bug
blocked-by: []
status: backlog
created: 2026-08-31
summary: "LATENT, with a named trigger. cparser.inc's four `TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32]` tests pick the 4-byte-slot va_arg helper; everything else falls to an else whose comment says `Cross (aarch64)` but whose condition is `<> TARGET_X86_64`, i.e. the 8-byte-slot path. xtensa and wasm32 are 32-bit and absent from the set -- the set is correct TODAY only because neither can compile a C program at all (`C program entry stub not implemented for this target yet`). The day either gains an entry stub it silently gets 64-bit varargs slots. Fix the set in the SAME commit as the stub."
---

# The 32-bit `va_arg` set is complete only because two targets cannot compile C

Found 2026-08-31 (frankwasm) auditing single-arm/enumerating `TargetArch` tests
for wasm32 holes — the population frank-rust's `refactor-a-target-dispatch-chains-fail-open`
sweep explicitly did not cover (it audited 27 dispatch *chains*; this is a
*set membership* test).

## Measured, binary `25178873db17`

A C program using `va_start`/`va_arg`/`va_end`:

| target | result |
| --- | --- |
| i386, arm32, riscv32 | **ok** — in the set, 4-byte slots |
| aarch64, x86-64 | **ok** — else branch, 8-byte slots, correct for both |
| **xtensa** | `error: C program entry stub not implemented for this target yet` |
| **wasm32** | `error: C program entry stub not implemented for this target yet` |

So the set names exactly the 32-bit targets that can compile C, and it is
**complete and correct as it stands.** This is not a live defect and must not be
"fixed" as one.

## Why it is filed anyway

The set is correct for a reason that has nothing to do with the set. It is
correct because two of its rightful members are unreachable — and the thing
making them unreachable (`compiler/cparser.inc`, the C entry stub) is exactly
the thing somebody will implement.

The four sites are `cparser.inc:1626`, `:1695`, `:1737`, `:1745`. The else they
fall into reads:

```pascal
if TargetArch <> TARGET_X86_64 then
  { Cross (aarch64): single GP-style save area ... one 8-byte-slot cross helper }
  helper := FindProc('__pxx_va_arg_cross')
```

The comment says **aarch64**; the condition says **everything that is not
x86-64**. Today those coincide. A new 32-bit target lands in the 8-byte-slot
path with a comment claiming it is aarch64 — silently, since varargs produce
wrong VALUES rather than a diagnostic, and the wrongness starts at the second
argument.

## The trigger, so this is findable at the moment it matters

**Whoever implements the C program entry stub for xtensa or wasm32 must add that
target to all four sets in the same commit.** Not afterwards: between the two
commits, C varargs on that target are silently wrong.

The cheap check is the same one that produced this ticket — compile a
`va_arg` C program for the new target and compare against gcc via
`tools/gcc_diff_probe.sh --target=<t>`.

## Not the fix

Do not paper over it by widening the set now. `TARGET_WASM32` in a list of
targets that cannot reach the code is a claim that will read as tested and is
not, and it removes the one thing that would make the real change necessary —
somebody noticing the target is missing. Leave the set honest and let the
trigger fire.

## Also worth doing when someone is in there

Reword the else's comment. `Cross (aarch64)` describes the only member it has
today, not the set it selects. Naming a branch after its sole occupant is what
made this take a measurement to see.
