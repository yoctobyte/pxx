---
prio: 60
track: A
status: backlog
owner: ""
---

# -O3: fuse `mov rax, rN` + `cdqe` into a single `movsxd rax, rNd`

Split out of `feature-opt-o3-register-pressure` (W1). It was item **(B)** of three
found by disassembling that campaign's own benchmark loop; filed separately
because it is dispatchable on its own and was otherwise going to live in an
umbrella's log.

- **Type:** feature (codegen — optimization) — **Track O**, file-ownership
  **Track A** (`compiler/ir_codegen.inc`), so it obeys A's gate: `make
  compiler/pascal26` (which *is* the byte-identical self-host fixedpoint) plus
  the repro.
- **Worth:** −1 instruction and −2 bytes per occurrence. Small, but it is in the
  inner loop of the shape the O campaign exists for.

## The observation

`three.pas`'s inner loop at `-O3`, HEAD `989e45c01`, reading a 4-byte resident
(`i`, resident in r12) and widening it for a 64-bit shift:

```
  91:  4c 89 e0        mov    rax,r12
  94:  48 98           cdqe
  96:  48 c1 e8 01     shr    rax,0x1
```

Five bytes and two instructions to get the LongInt value of `i` into rax
sign-extended.

## The tempting fix is the wrong one

The `cdqe` is provably a no-op *today*: every write to a 4-byte resident's
register re-normalises it, so the upper half is already the sign extension.
The emitter does this explicitly — in the same loop:

```
  b3:  49 81 c4 01 00 00 00   add    r12,0x1
  ba:  4d 63 e4               movsxd r12,r12d
```

and at residency init (`movsxd rax,eax; mov r12,rax`). So **deleting the `cdqe`
would be correct.** Do not do that. It is an elision that depends on an
invariant holding at every write site, forever, maintained by code in a
different file — exactly the kind of correctness argument W1 slice 8 deliberately
refused. Its failure mode is a silently wrong value, and it decays the moment
someone changes how residents are normalised.

## The fix that needs no invariant

Emit the widening explicitly instead of eliding it:

```
  49 63 c4        movsxd rax, r12d
```

Three bytes, one instruction, and it sign-extends the low 32 bits *by
construction* — it is correct whatever the upper half of r12 holds. Same net
effect as `mov` + `cdqe`, strictly better encoding, and no dependence on a
property maintained elsewhere.

Encoding: `movsxd r64, r/m32` is `REX.W [+B] 63 /r`. For `rax <- rNd`:
`REX = $48 or Ord(N >= 8)`, then `$63`, then ModRM `$C0 or ((N - 8) and 7)`.
(`49 63 C4` for r12: REX.W+B, mod=11, reg=000=rax, rm=100=r12.)

## Scope

Wherever a 4-byte-typed resident is read into rax and immediately widened. The
pattern to look for is `EmitLoadVar`'s resident arm (`mov rax, rN`) followed by
the sign-extend the caller emits for a 64-bit operation. Peephole at the emit
site, not a post-pass over bytes — the pipeline decision in the umbrella
(**do NOT post-rewrite bytes**) applies.

## Gate

`-O3`-gated like every pass in this campaign. Needs its **own** `-O0`/`-O3`
control pair against one expectation (standing rule 1 in the umbrella: the
fixedpoint gate is structurally blind to an `-O3`-only defect), with **band**
rows — adjacent values, not far-apart memorable ones (standing rule 4). A row
that would catch this specifically: a negative 4-byte value widened and used in
a 64-bit context, where dropping or mis-encoding the extension gives a large
positive number rather than a crash.

Verify non-vacuity by breaking the encoding on purpose, and **verify the break
changes the emitted bytes**, not merely the source (standing rule 4's second
half — a break that is an identity looks exactly like a vacuous test).

## Links

- Umbrella: `feature-opt-o3-register-pressure` (W1)
- Sibling split out at the same time: `feature-opt-o3-operand-order-for-non-commutative-binops` (item C, worth −2)
