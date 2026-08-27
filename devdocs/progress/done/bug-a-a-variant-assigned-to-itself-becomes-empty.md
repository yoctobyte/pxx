---
slug: bug-a-a-variant-assigned-to-itself-becomes-empty
track: A
prio: 55
type: bug
blocked-by: []
status: done
summary: "`v := v` on a Variant does not leave it alone — it EMPTIES it, on every target, silently. FPC leaves the value. Pre-existing on pinned. The retain-before-clear that guards the aliased case protects the payload's REFCOUNT and not the slot BYTES: PXXVarClear then zeroes all 16 bytes of a slot that is also the source, and the copy that follows copies the zeros."
owner: claude-A-S
---

# A variant assigned to itself becomes Empty

## Repro

```pascal
program vself;
var v: Variant; s: AnsiString;
begin
  s := 'ab'; v := s;
  writeln('before: ', v);
  v := v;
  writeln('after : ', v);
  v := 42; writeln('int before: ', v); v := v; writeln('int after : ', v);
end.
```

| | before | after | int before | int after |
| --- | --- | --- | --- | --- |
| pxx HEAD x86-64 | `ab` | *(empty)* | `42` | *(empty)* |
| pxx **pinned** x86-64 | `ab` | *(empty)* | `42` | *(empty)* |
| **fpc -O1** | `ab` | **`ab`** | `42` | **`42`** |

Pre-existing, not a regression, and not target-specific: the same shape is in the
`IR_VAR_STORE` / `tk = tyVariant` arm of x86-64, i386, arm32, aarch64 and (as of
[[bug-a-riscv32-codegen-has-no-variant-support]]) riscv32.

## Root cause — measured, not reasoned

Every backend's variant-to-variant arm is:

```
    <src addr>              ; PXXVarRetain(src)
    push src
    <dest addr>             ; PXXVarClear(dest)
    pop src
    copy 16 bytes src -> dest
```

The retain-before-clear is there precisely for the aliased case, and it is doing
its job — but only for **the payload's refcount**. `PXXVarClear`
(`compiler/builtin/builtinheap.pas`) ends with

```pascal
  PXXMemZero(v, 16);
```

so when `src = dest` it zeroes the **slot bytes it is about to be the source
of**, and the copy that follows faithfully copies sixteen zero bytes. A zeroed
slot is tag 0, i.e. Empty — which is exactly what prints.

The string case additionally leaks: the retain took the payload to +2, the clear
released it back to +1, and then nothing owns the +1 the zeroed slot no longer
references.

## Fix shape

Two candidates; pick deliberately rather than by which is fewer lines.

1. **Skip the store when the addresses are equal** — compare src and dest at
   runtime and branch over the whole clear+copy. Cheapest, and it is what the
   aliasing actually means: a self-assign is a no-op. One branch per backend, six
   backends.
2. **Copy the 16 bytes to a scratch before clearing** — the general answer, and it
   also fixes PARTIAL overlap, which the equality test does not (`r.a := r.b`
   where both are variant fields of one record cannot alias, so there may be no
   partial-overlap case to fix — check before paying for it).

Prefer (1) unless (2) turns out to be needed; state which in the resolution.

Whichever wins, it is six copies of the same edit, which is the shape
`devdocs/dev/normalise-dont-special-case.md` warns about: consider whether the
guard belongs in `PXXVarClear`/the copy helper (one place, in Pascal) rather than
in each backend's emitter.

## Found by

The hazard probe written while landing
[[bug-a-riscv32-codegen-has-no-variant-support]] — riscv32 matched the x86-64
oracle on every row, including this one, because the oracle is wrong too. Filed
rather than chased: it is a separate mechanism from "riscv32 has no variant arms
at all", it spans six backends and the runtime, and it had no business riding
along on that fix.

## Gate

Track A's, plus the repro above matching FPC on x86-64, i386, arm32, aarch64 and
riscv32, plus a heap-growth row for the string case (a `v := v` loop must stay
flat).


---

## Resolution (2026-08-27)

Took **neither** of the two fix shapes the ticket proposed. Both of them treat
the zeroing as a given and work around it; the zeroing is the defect.

### What actually landed

`PXXVarClear` was one routine doing two things — *release the managed payload*
and *reset the slot to VT_EMPTY* — and the assignment path only ever wanted the
first. The second is dead work there even when nothing aliases: the copy on the
very next instruction overwrites all sixteen bytes. So the routine is split:

```pascal
procedure PXXVarReleasePayload(v: Pointer);   { the two release tests, no zeroing }
procedure PXXVarClear(v: Pointer);            { = ReleasePayload + PXXMemZero(v, 16) }
```

and every backend's variant-to-variant arm calls `ReleasePayload`. x86-64's
clear is a hand-emitted blob rather than a call into Pascal, so
`EmitVariantClearBody` took a `zeroSlot` flag and `EmitVariantBlobs` emits a
second blob from the same body — ~96 bytes of image, once, against a branch at
every variant store.

**Self-assignment then falls out as the degenerate case** — retain (+1),
release (-1), copy a slot onto itself — with no test to get wrong and nothing in
the hot path. That matters more than it sounds: option 1's `src = dest` test
would have had to be a RUNTIME comparison to catch aliasing the compiler cannot
see, and the new test's `Both(v, v)` row is exactly that case.

Five backends: x86-64, i386, arm32, aarch64, riscv32. (xtensa has no variant
arms at all.)

### Measured

| | pinned | HEAD |
| --- | --- | --- |
| `test_variant_self_assign_is_a_no_op` verdict | **FAILED** | `ALL OK` |
| peak RSS, 200k self-assignments | **7680 kB** | **392 kB** |

The RSS row is the leak half the ticket predicted: the retain took the payload
to +2, the clear put it back to +1, and the zeroed slot then referenced
nothing.

Output is **byte-identical to `fpc -O1`'s** on the same source, on x86-64,
i386, arm32, aarch64 and riscv32.

### Coverage

`test/test_variant_self_assign_is_a_no_op.pas` — string, integer and double
payloads; the `var`-parameter alias codegen cannot see; the ordinary two-slot
case (the path the fix touched, so it has to say out loud that it still works);
and the 200k-iteration leak loop. Wired into **test-core** with both the
verdict and the full expected transcript, and into the i386 / aarch64 / arm32 /
riscv32 cross blocks. It compiles under `fpc` unmodified — `LongInt` not
`Integer`, because FPC's default mode makes `Integer` 16-bit — so it is its own
oracle.

The earlier variant differentials (`test_cross_variant_payload_widths`,
`test_variant_comparison_coerces_a_stringy_operand`, `test_variant`,
`test_variant_ops`, `test_variant_string`) re-checked x86-64 vs riscv32: all
still agree.

### Note for whoever touches this next

The BOXING path (`EmitVariantFill*`, `v := 42`) still calls the full
`PXXVarClear`, and its fill also overwrites all sixteen bytes immediately — so
the same dead zeroing is there. Left alone deliberately: it has no aliasing
hazard (the source is a scalar, not a slot), so it is a size/speed question and
not a correctness one, and it had no business riding along on a bug fix.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
