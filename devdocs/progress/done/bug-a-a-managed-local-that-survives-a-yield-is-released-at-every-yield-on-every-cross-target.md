---
track: A
prio: 70
type: bug
blocked-by: []
summary: "FIXED: `if CurProcIsStackless then Exit;` hoisted to the top of EmitManagedLocalCleanupForTarget, so a generator step function no longer releases its managed locals at every yield -- they are the generator's live state. Was a SILENT WRONG VALUE (exit 0) on i386/arm32/aarch64: `acc` came back as the loop counter's string, `parts` overwritten. wasm32 exits earlier and is still unchecked."
status: done
---

# A managed local that survives a yield is released at every yield (cross only)

- **Track A.** Measured 2026-09-04 by frankb-78 while adding the `tyClass` arm
  to the five cross arms of `EmitManagedLocalCleanupForTarget`
  (`bug-a-cross-backends-neither-retain-into-a-variant-nor-release-a-class-local-and-the-two-must-move-together`).
  Found because that arm needed the guard and the guard was not there.

## The repro

```python
def gen(k):
    acc = ""
    n = 0
    i = 0
    while i < k:
        acc = acc + "x"
        n = n + i * 1000000007
        yield acc + "|" + str(len(acc)) + "|" + str(n % 97)
        i = i + 1

out = []
for v in gen(6):
    out.append(v)
print(out)
```

| target | output |
| --- | --- |
| CPython | `['x\|1\|0', 'xx\|2\|41', 'xxx\|3\|26', ...]` |
| x86-64 | identical to CPython |
| i386 | **SIGSEGV** |
| arm32 | **SIGSEGV** |
| aarch64 | `['x\|1\|0', '\x00\x00\|3\|41', '\x00\x00\|3\|26', ...]` — wrong value, no crash |

Compiles fine on all four; the divergence is at runtime.

## The cause, and why x86-64 is the one that is right

`EmitManagedLocalCleanup` (x86-64, `symtab.inc`) opens with

```pascal
  if CurProcIsStackless then Exit;
```

and its comment explains it: a stackless generator step function RETURNS at
every yield and is re-entered at the next one, so its locals are not going out
of scope on that path — they are the generator's live state, checkpointed into
the heap instance and restored on resume. Releasing them there frees the very
objects the instance still points at.

`EmitManagedLocalCleanupForTarget` (`ir_codegen.inc`) has five arms — i386,
arm32, aarch64, xtensa, riscv32 — and **not one of them has that guard.** Each
opens with `if CurProc >= 0 then` and walks straight into the release chain, so
every string, variant, promo-int, record and dynamic-array local of a step
function is released at each yield. Pascal never sees it (its class locals are
not refcounted and it has no NilPy generators), which is why the hole survived.

wasm32 releases in `WasmEmitManagedLocals(release)` instead and is **unchecked
by this ticket** — it needs the same question asked of it.

## The fix

Hoist the same early exit into `EmitManagedLocalCleanupForTarget`, beside the
`TARGET_WASM32` exit that is already there:

```pascal
  if CurProcIsStackless then Exit;
```

The `tyClass` arm added by the sibling ticket carries `(not CurProcIsStackless)`
inline as a stopgap, so it is already correct; that clause becomes redundant
once the whole-function guard lands and should be deleted in the same commit,
with the comment's stopgap paragraph.

## The guard this needs

The repro above IS the positive control — it must go from SIGSEGV to CPython's
output on i386 and arm32 and from corrupted strings to correct on aarch64. Wire
it on all four targets; x86-64 is the oracle and is already green, so an
x86-64-only row would pass before and after and prove nothing.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f891bbe8e.

## Resolved — one line, at the top of the procedure, not five times

`if CurProcIsStackless then Exit;` now sits in
`EmitManagedLocalCleanupForTarget` beside the existing `TARGET_WASM32` exit, so
it covers every kind on every cross arm rather than being repeated per target.
The `(not CurProcIsStackless)` clause the sibling ticket's `tyClass` arm carried
as a stopgap is deleted in the same commit, together with the paragraph that
explained it — a stopgap left in place after the general fix reads as a second,
narrower rule and invites someone to trust it.

**The test is `test/test_nilpy_generator_managed_local_survives_yield.npy`**,
wired on x86-64 (oracle only), i386, aarch64 and arm32. `acc` and `parts` must
SURVIVE the yield; a local rebuilt inside the loop body cannot see this defect
at all, because its release lands after its last use.

| target | pin v403 | HEAD |
| --- | --- | --- |
| x86-64 | correct | correct — **green both sides, so it guards nothing** |
| i386 | `['x\|1\|0', '1\|1\|0,1', '2\|1\|0,2,2', ...]` | correct |
| arm32 | same as i386 | correct |
| aarch64 | same as i386 | correct |

`acc` came back as the loop counter's string and every earlier element of
`parts` was overwritten — the freed blocks handed out again. Exit code 0 on all
three: **a silent wrong value, not a crash**, which is why nothing had caught
it. The closely related string-only shape SIGSEGVs on i386 and arm32 instead,
so the class spans wrong-value to crash.

**What this fix does NOT cover, measured rather than assumed.** The first draft
of the test carried a promo-int local and stayed red on i386 and arm32 after
this change: a promotable-int local in a generator truncates to 32 bits on those
two targets, identically on the pin, and reproduces with no managed local
anywhere in the program. Removed from this test on purpose and filed as
`bug-a-a-promotable-int-local-in-a-generator-truncates-to-32-bits-on-i386-and-arm32`.
Leaving it in would have made this row fail for a defect it does not guard.

**wasm32 is still UNCHECKED** — it exits before this guard and releases in
`WasmEmitManagedLocals(release)` instead. Nobody has asked that path the
question; that is not a claim that it is fine.

## Follow-up the same day — the blanket exit was itself half wrong

`f891bbe8e` hoisted `if CurProcIsStackless then Exit;` into
`EmitManagedLocalCleanupForTarget`, matching x86-64's twin. That closed this
ticket and was the right shape for one commit — but the twin it matched was
*also* over-broad, which only showed up when the next ticket in the group needed
the step function's cleanup to run for a different reason.

A stackless step function's frame holds two populations: its **persistent
slots**, which are the generator's live state and must not be released at a
step return, and its **hidden temps**, minted during `IRLowerAST` after
`AssignStacklessSlots` has run, which die inside one statement and are ordinary
locals in every sense. The blanket exit is correct about the first and wrong
about the second, and the second leaked on both the return path and the unwind
path.

Replaced by one per-symbol predicate, `StacklessPersistentSlotSym(i)` =
`CurProcIsStackless and SymGenSlot[i] >= 0`, applied on the cleanup loops of
both emitters and in `ProcHasManagedLocalCleanup` — see
`bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad`
for the measurement. **This ticket's own test is the control that says the fix
did not swing back too far**: `test_nilpy_generator_managed_local_survives_yield`
is exactly the program that breaks when a slotted local IS released, and it
stays green on all four targets.
