---
track: A+C
prio: 60
type: bug
status: open
found: 2026-08-31
found-by: frankC
owner: frankC
summary: "A C function taking a struct BY VALUE is compiled to take a POINTER. Self-consistent inside pxx, so every existing test passes; gcc passes the struct bytes, our callee dereferences them as an address, SEGFAULT on x86-64 and i386. ROOT CAUSE FOUND and it is a DELIBERATE DESIGN, not an oversight: cparser.inc:11107 marks every C struct param isRef:=True with a comment saying so -- the caller copies to a temp and passes &temp, which gives correct by-value SEMANTICS at any size but is not the ABI gcc implements. Pascal differs (pasparser_proc.inc:2284): <=8 bytes by value, >8 by reference, so Pascal is SysV-correct below 8 bytes by construction and equally wrong above it. SysV wants eightbyte classification up to 16 and MEMORY beyond. So the work is REPLACING a working convention with the psABI one, not repairing a broken one -- bigger than the first filing implied. GATE BUILT and RED: `make test-c-abi-mixed-link` (gcc main + pxx object, both call directions, x86-64 and i386; no gcc cross exists for the other targets), unwired while this is open. If split, split at 8 bytes: <=8 occupies one slot under both schemes so it cannot shift a later argument, and above 8 the slot count changes, which is where the xtensa two-of-three state turned data loss into active corruption."


---

# A by-value struct parameter is passed as a POINTER to every C-ABI callee

`ABIParamSlotIsPointer` (`compiler/abi.inc`) answers True for `tyRecord`, so a
by-value struct parameter occupies one pointer-sized slot everywhere in the
C ABI. Both sides of a pxx-only program agree, so nothing in the suite fails.
Across a real C boundary the callee dereferences the caller's *data*.

## Repro — three runs, and the third is the control

```c
/* pxx side */ struct Pair { int a; int b; };
               int take_pair(struct Pair p) { return p.a * 100 + p.b; }
/* gcc side */ struct Pair p = {3, 7}; printf("take %d\n", take_pair(p));
```

| both sides | result |
| --- | --- |
| gcc + gcc (`-m32` and native) | `take 307` — the oracle |
| pxx + pxx (i386) | `take 307` — self-consistent, which is why this was invisible |
| **gcc caller -> pxx callee** | **SEGFAULT**, x86-64 *and* i386 |

Control, same link shape, scalar parameters instead of a struct:
`take_ints(3,7)` -> `ints 307`. So the link, the object and the calling
sequence are all fine; the struct is the variable.

## Why no existing test sees it

`test-c-abi-cross`'s three subjects are all pxx-compiled on both sides —
deliberately, since they were built to catch a convention *change*, which is
self-consistent by construction either way. `test-c-abi-glibc-oracle` does
cross a real boundary, but only with scalars and a variadic tail through
glibc's `dprintf`; no glibc entry point in it takes a struct by value.
**The gap is the same one this ticket's family keeps rediscovering: a
self-consistent pair cannot judge a convention.** frankA's sharper form, from
the probe that could not fail: **a differential oracle only covers the
population where the two implementations can actually disagree, and a calling
convention is agreed by construction inside one implementation — so
self-consistency is not evidence about an interface.** The corollary is the
gate this ticket needs: the new subject must be a MIXED LINK, and no amount of
strengthening a pxx-vs-pxx subject substitutes for it.

## Scope — bigger than the one line

Changing the predicate is not the fix. The psABI wants the aggregate's own
bytes classified: SysV x86-64 splits into eightbytes with INTEGER/SSE classes
(and MEMORY past two), AAPCS64 has the HFA/HVA rule plus an 8-byte-slot copy
past the banks, AAPCS32 has its own. `ABIA64CdeclArgSlot` currently advances
NSAA by exactly 8 per stack argument, which is correct only while every slot is
a pointer. The callee spill (`EmitParamSpillsForTarget`) needs the mirror.

Returns are NOT in scope and appear to be right: `RetViaHiddenDest` implements
the hidden-destination convention and `cee_pairsum` matches gcc on four
targets.

**A consequence for whoever takes this, recorded here rather than in an audit
note because it is a property of the FIX and not of today's code** (frankA):
`ABIA64CdeclArgSlot` advancing NSAA by exactly 8 per stack argument is correct
*only while every slot is a pointer*. It is right today for that reason, and it
becomes wrong on the first commit that classifies aggregates properly. The
direct arm, the indirect arm and `EmitParamSpillsForTarget` all read that one
oracle, so the advance and the three readers move together or not at all.

## Found by

frankA asked whether the `ldr x9` single-word move in the aarch64 stack half
truncates a by-value aggregate spilled past the register bank, built the case,
and measured it MATCHING — because both sides were pxx. The negative result was
sound and the hypothesis was unreachable: the move is correct *by construction*
precisely because the slot is a pointer. Chasing why it could not fail is what
found this.

## Gate — BUILT, and RED

`make test-c-abi-mixed-link` (deliberately NOT wired into any suite while this
ticket is open; wire it in when it closes). `test/c_abi_mixed_link_pxx.c` is
compiled by pxx to an object; `test/c_abi_mixed_link_main.c` is compiled by gcc
and links against it. **Both directions**, because they fail independently:
`take_*` is a pxx CALLEE reading what gcc laid down, `relay_*` is a pxx CALLER
laying down what a gcc callee reads. Shapes hit the SysV boundaries — 1
eightbyte / 2 eightbytes / MEMORY past 16 / all-SSE / mixed INTEGER+SSE /
sub-word / an aggregate arriving after the GP bank is nearly full.

Current state: `2 of 2 targets measured`, **FAIL x86_64, FAIL i386**, both a
segfault. gcc-on-both-sides gives the expected text, so the values are gcc's
and not ours.

**x86-64 and i386 only, and that is a hard limit, not a shortcut:** there is no
gcc cross for arm32, aarch64 or riscv32 on this box, so no mixed link is
constructible for them. The glibc substitute oracle does not extend here either
— it needs a glibc entry point that takes a struct by value.

## What the investigation added (2026-08-31, later)

**Instruction-level confirmation.** `objdump` of the pxx object:

```
take_p2:  mov %rdi,-0x8(%rbp)      ; store the incoming register
          mov -0x8(%rbp),%rax
          movslq (%rax),%rax       ; DEREFERENCE it
```

gcc puts the struct's eight bytes *in* `rdi` (0x0000000700000003 here), so the
callee dereferences data as an address. Not inference: that is the emitted code.

**The duplication blocker named in `ir_codegen.inc` is GONE, and its warning was
stale in the more dangerous direction.** That comment said cparser.inc carried a
second full SysV classification and *"do not fix one of these two without the
other"*, citing `cparser.inc:11282`. The collapse was already done
(`refactor-a-collapse-the-c-frontend-sysv-prologue-copy`, in `done/`), and the
cited line had drifted onto unrelated `va_arg` code — a real line that was not
the thing it named. Corrected in place: there is now **one** SysV prologue, so
this fix has one site, not two.

**i386 has a PRIOR gap that must be closed first.** i386 refuses a by-value
record in *any* convention, not just the C one — a plain Pascal
`function TakeP2(p: TP2)` gives `target i386: only ordinal/pointer parameters
supported yet` (`ir_codegen.inc:1279`, since 2797638e5, 2026-08-21). x86-64,
arm32, aarch64 and riscv32 all compile and run that same Pascal. So i386 needs
by-value aggregates at all before it can have them *correctly*.

## ROOT CAUSE, and it is a DELIBERATE DESIGN, not an oversight

Settled with gdb (`-g`, then `disassemble` — `objdump -d` reads nothing from a
pxx executable, which carries no section headers; gdb reads the program headers).
The IR is identical for both frontends (`lea sym=p` then `field`), so the
divergence is entirely in how the symbol is FLAGGED.

**`cparser.inc:11107` marks every C struct parameter `isRef := True`, on
purpose, and says so:**

> *"A C record param is by-value but passed via the by-ref ABI (an 8-byte
> pointer slot the callee derefs); the caller copies the record to a temp and
> passes &temp (IRLowerCallArg), giving true by-value with correct field access
> for records of ANY size (the inline 8-byte slot could not hold >8B)."*

That is a coherent scheme. It delivers correct by-value *semantics* at every
size — it is simply not the *ABI* gcc implements. `isRef` then makes
`ABIParamSlotHoldsValueAddr` true, and `IR_LEA` lowers to `mov` (load the
pointer) instead of `lea` (address of the slot).

**Pascal's rule is different and size-dependent** (`pasparser_proc.inc:2284`,
*"Records larger than a qword are passed by reference"*):

| | <= 8 bytes | > 8 bytes |
| --- | --- | --- |
| Pascal | by VALUE in a register (`isRef` False -> `lea`) | by reference (`mov`) |
| C | by reference, ALWAYS | by reference |
| **SysV wants** | eightbyte-classified in registers, up to 16 | **MEMORY: bytes on the stack** |

Measured, x86-64, same 8-byte `{int a, b;}`:

```
Pascal TakeP2:  mov %rdi,-0x8(%rbp) ; lea -0x8(%rbp),%rax ; movslq (%rax)
C      take_p2: mov %rdi,-0x8(%rbp) ; mov -0x8(%rbp),%rax ; movslq (%rax)
```

One instruction apart. Pascal's arm is SysV-correct here by construction; the C
arm dereferences the data gcc put in `rdi`. Pascal's `TakeP4`/`TakeP6`/`TakeD2`
all use `mov`, so Pascal is equally non-psABI above 8 bytes — it just happens to
agree below it.

**So this is not "restore a broken path", it is "replace a working convention
with the psABI one"** on the C side, and extend it above 8 bytes on both. That
is a larger and more deliberate change than the original filing implied, and it
is why the estimate belongs in the ticket rather than in someone's head.

## THE OBVIOUS FIRST ATTEMPT, TRIED AND MEASURED — it does not work

Do not repeat it. `cparser.inc:11107` changed from `True` to
`RecSize(precid[i]) > 8`, so C's rule matches Pascal's at the 8-byte boundary.
Self-host converged; binary `c93061a625bd`. Then, on x86-64:

- **The CALLEE half becomes correct.** `take_p2` emits `lea -0x8(%rbp),%rax`
  instead of `mov`, and an 8-byte struct handed over by a real gcc caller reads
  back correctly: `take 307`, where the same link segfaulted before.
- **The CALLER half breaks on every target.** A pxx caller still copies to a
  temp and passes `&temp`, so a pxx callee now reads the POINTER's bits as the
  struct's fields. Measured on a pxx-only C program that was correct before:

  | | before | with the probe | gcc |
  | --- | --- | --- | --- |
  | x86-64 | `37 91` | `-587090340 91` | `37 91` |
  | arm32 | `37 91` | `-981461088 91` | `37 91` |
  | aarch64 | `37 91` | `-272680545 91` | `37 91` |
  | riscv32 | `37 91` | `-623531480 91` | `37 91` |
  | i386 | `37 91` | **compile error** | `37 91` |

  A live address rendered as a decimal number — the same signature as
  [[bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address]]. Reverted
  with `git checkout --`; all five targets confirmed back at `37 91`.

**And it corrects the "safe split" advice this ticket used to give.** That advice
said a <= 8-byte record occupies ONE slot under both schemes, so switching it
cannot shift a later argument. The claim is TRUE and it is NOT the safety
property — nothing shifted above, and the values were still garbage. The binding
constraint is that **the caller and the callee must agree about what the slot
CONTAINS**, and the caller's half lives in shared IR lowering
(`IRLowerCallArg`, `ir.inc:3250`), not in the per-parameter flag. So the pair
moves together or not at all, and size is not a seam you can cut along.

**i386 nuance, correcting an earlier note in this ticket.** i386 refuses by-value
records in the *Pascal* convention (`ir_codegen.inc:1279`), but C structs compile
and run correctly on i386 *today* — precisely BECAUSE the C frontend routes them
through the by-ref ABI. The deliberate design is what makes i386 work at all, so
"fix i386's prior gap first" is a real prerequisite and not an aside: on i386
this change cannot even be attempted until by-value records exist there.

**Why this was not started here:** partial aggregate classification is worse
than none. The precedent is in this repo — a two-of-three xtensa state
*"turned the data loss into active corruption"*, because a caller pushing two
words and a spill consuming one shifts every later parameter rather than
failing. The same applies per-target here, so it lands whole or not at all.
