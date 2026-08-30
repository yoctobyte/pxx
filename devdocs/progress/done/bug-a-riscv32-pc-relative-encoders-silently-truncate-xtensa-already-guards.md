---
slug: bug-a-riscv32-pc-relative-encoders-silently-truncate-xtensa-already-guards
track: A+S
prio: 60
type: bug
found: 2026-08-30
found-by: frankS
owner: frankS
status: done
---

> **prio 50 → 60 by the coordinator, 2026-08-30.** Not a disagreement with the filer's
> judgement — an argument the filer could not make about its own ticket. Three facts compound:
> the encoder emits **silently wrong code** rather than failing; `test_overflow_qplus_narrow`
> already sits at **758 KiB against JAL's ±1 MiB**, so this is 74% of the way to firing on a
> test we run today, not a theoretical limit; and **the fix template already exists on the
> sibling backend**, so the cost is low and the design question is settled. The repo has also
> already paid for this defect twice — riscv32's `IR_JUMP_IF_FALSE` emits bne-skip + jal
> because a bare `beq` truncated and branches landed inside unrelated code (chess perft
> counted 164), and xtensa's version cost "a disassembly and the arithmetic
> 262591-262144=437". **Both times the call site was worked around and the encoder was left
> sharp.** Guarding it is the root-cause fix those two microfixes deferred.
>
> Expect the guard to **turn some silent miscompiles into compile errors** — that is the
> point, and it is what surfaced the xtensa veneer ticket's five programs. Budget for new
> reds, do not read them as a regression.


# riscv32's PC-relative encoders silently truncate; xtensa already guards

`compiler/rv32enc.inc` masks every PC-relative offset into its bit field with no
range check. `compiler/xtensaenc.inc` checks four forms through one helper. Same
defect, same family, fixed on one backend and not its sibling.

```pascal
{ rv32enc.inc — EncodeRISCVJAL, and BEQ/BNE are the same shape }
i20    := (offset shr 20) and 1;
i19_12 := (offset shr 12) and $FF;
...                                  { no check; out-of-range just loses bits }

{ xtensaenc.inc — the guard that exists }
XtensaRelCheck(offset - 4, -131072, 131071, 'j');
XtensaRelCheck(offset - 4, -128, 127, 'conditional branch');
```

`grep -c 'Error(' compiler/rv32enc.inc` → **0**.

| encoder | range | checked? |
| --- | --- | --- |
| `EncodeRISCVJAL` | ±1 MiB | **no** |
| `EncodeRISCVBEQ` / `BNE` | ±4 KiB | **no** |
| `EncodeRISCVJalr` (imm) | ±2 KiB | **no** |
| xtensa `j` / `call0` / `call8` / cond branch | ±512 KiB, ±128 B | yes |

## This is armed, not theoretical, and the repo has already paid for it twice

**Once on riscv32.** `IR_JUMP_IF_FALSE` in `ir_codegen_riscv32.inc` does not emit
a bare `beq` — it emits `bne`-skip + `jal`, and the comment says exactly why:

> *"B-type immediates reach only ±4KB, and a large routine (a flattened
> stackless generator, a big MakeMove) silently TRUNCATED the offset — branches
> landed inside unrelated code (chess perft counted 164)."*

So the call-site was worked around and **the encoder was left sharp.**

**Once on xtensa**, as `bug-a-xtensa-pc-relative-encoders-silently-truncate-an-
out-of-range-offset`, whose own comment records the cost of diagnosing it:

> *"A wrong PC three functions away from the cause… The offset was not close to
> the boundary and no diagnostic mentioned a range, so nothing pointed at the
> encoder; it took a disassembly and the arithmetic 262591-262144=437 to name
> it."*

That fix added `XtensaRelCheck` and stopped there. riscv32 was not swept —
`devdocs/dev/normalise-dont-special-case.md`'s "fix one arm, grep for the
sibling", where the sibling is a whole other backend.

## Why JAL is the live one

`jal` is ±1 MiB and carries every forward jump plus the label-fixup path. The
veneer ticket
([[bug-a-xtensa-cannot-build-a-program-over-512-kib-of-code-call0-has-no-veneer]])
measures `test_overflow_qplus_narrow` at **758 KiB of code on riscv32** — within
a factor of 1.4 of the limit, in a test that exists today. xtensa at the same
size gets a compile error naming the range; riscv32 would get a jump into the
middle of an instruction.

Measured while checking whether frankA's `bug-a-a-rel8-jump-patch-truncates-
silently-when-its-span-grows` had a counterpart on the 32-bit cross backends. It
does, on one of the two.

## The fix, and what it will do

Mirror `XtensaRelCheck`: one `RISCVRelCheck(v, lo, hi, what)` in `rv32enc.inc`
plus a call in JAL, BEQ, BNE and Jalr. ~15 lines.

**Expect it to turn some silent miscompiles into compile errors, and treat that
as the point rather than a regression.** That is what happened on xtensa: the
guard is what made `call0 displacement -131454 is outside the encodable range`
visible, which is what produced the veneer ticket and its 5 named programs.
A guard that fires is a defect being surfaced, not created.

`{$ifdef}` note for whoever takes it: the check must be on the SIGNED range, not
"did the mask change the value" — masking is correct for negative offsets
(two's complement is what the field wants), and the naive form would reject
every backward branch. `xtensaenc.inc` states this and is the template.

## Not fixed here

`rv32enc.inc` is outside the bounded grant frankS held (`ir_codegen_riscv32.inc`
and `ir_codegen_xtensa.inc`). Filed rather than widened.

## Gate

`make compiler/pascal26` to fixedpoint, then the 129-source cross differential on
riscv32 for programs that newly refuse to compile — each one is a real find and
wants its own ticket or a veneer, not a relaxed bound.

## Log

- 2026-08-30 — **fixed.** `RISCVRelCheck` in `rv32enc.inc`, mirroring
  `XtensaRelCheck`: `jal` (`EmitJType` + `EncodeRISCVJAL`, ±1 MiB) and the
  conditional branches (`EmitBType`, `EncodeRISCVBEQ`, `EncodeRISCVBNE`,
  ±4 KiB). Signed-range test, not "did the mask change the value" — the trap the
  ticket warned about. Also checks the low bit, because J/B immediates encode
  bits [20:1] and [12:1] and DROP bit 0 rather than rejecting it.
- 2026-08-30 — resolved, commit PENDING-COMMIT.

### The prediction was right, and it was measured both ways

The ticket said to expect silent miscompiles to become compile errors. On a
generated 200-procedure program, same HEAD, same source:

| | result |
| --- | --- |
| with the guard | `error: target riscv32: jal displacement 11315580 is outside the encodable range -1048576..1048574` |
| without it | `ok: [code=11315212B]` — and the binary **segfaults**, exit 139, no output, where the x86-64 oracle prints `early=41 / acc=-6` |

### The corpus does not test this guard, and that is worth saying out loud

The 129-source differential is unchanged (111 MATCH / 3 DIFF / 14 CFAIL,
lost=0 gained=0). Nothing in it is near ±1 MiB — which is the expected result
and also means **the corpus proves only that the guard does not misfire**. What
it does prove is the half that is easy to get wrong: every backward branch in
111 programs went through the signed-range test without a false refusal. The
generated program above is what proves the guard fires.

### Scope note

PC-relative forms only, matching `xtensaenc.inc`, which also guards only its
PC-relative forms. The 12-bit I-type and S-type immediates (frame offsets on
loads/stores) mask the same way and are a real sibling of this defect, but they
are a different failure (a wrong ADDRESS, not a wrong PC) with a much larger
blast radius if a legitimate large frame trips it. Not widened here.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
