---
slug: bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet
track: C
prio: 35
type: bug
blocked-by: []
status: backlog
created: 2026-08-31
summary: "HALF DISCHARGED 2026-09-04, half still armed, and the ticket's own hard requirement was met. cparser.inc's four `TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32]' tests now read `[..., TARGET_XTENSA]': that widening landed in 233e693bb, THE SAME COMMIT as the xtensa C entry stub, which is what this ticket asked for. So xtensa can no longer silently take the 8-byte-slot else arm. Verified by running, not by reading: test/c_crtl_syscall_guarded_bodies.c and four vararg probes build and run under qemu-xtensa and match the gcc oracle. NOTE the widening alone was NOT sufficient -- with the set correct, 64-bit variadic arguments were still wrong for two further reasons (the direct-call ladder never classified a tail argument, and the caller's even-word pad disagreed with the walk's packed align=4), fixed in 7574a5f8d; membership in the 4-byte set is necessary and does not by itself make a target's varargs correct. wasm32 IS STILL ABSENT from the set and the trigger stays armed for it, gated only by bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it -- whoever lands that stub owes the same one-line widening in the same commit."
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

## 2026-09-04 — the xtensa half, discharged the way the ticket asked

`233e693bb` landed the xtensa C entry stub and the four set widenings together,
so the window this ticket was filed to prevent never opened.

**The requirement earned its keep, and it was still not enough.** With xtensa in
the 4-byte set, `printf("%llx", v)` still printed `55667788` for
`0x1122334455667788`, because two other things were wrong (see `7574a5f8d`).
Worth recording because the natural reading of "fix the set in the same commit"
is that the set IS the fix — it is the precondition. Anyone landing the wasm32
half should plan to run a `%lld` probe against the oracle, not just grep that
the target appears in four lists.

`wasm32` remains outside the set. The trigger is unchanged and the same commit
rule applies.
