---
track: A
prio: 60
type: bug
status: done
blocked-by: []
summary: "FIXED on x86-64 and aarch64. alloca moved the stack pointer under the value model's own expression stack, so a value pushed before an alloca and popped after read the alloca'd hole -- `a + (long)(alloca(32) != 0)` returned 1 for 101 on both targets, with no call in it for the frontend hoist to catch. Both backends now carve the hole at the bottom of the fixed frame and relocate the live region down to make room; x86-64 also saves its call sequence's caller-rsp as a delta from that base. Regression test test/c_alloca_expression_stack.c, 17 rows, both targets."
owner: frank-user-a
---

# alloca inside a call sequence corrupts the restored stack pointer

## The mechanism

`ir_codegen.inc`, the x86-64 `IR_CALL` path:

```
mov r11, rsp ; and rsp, -16 ; push r11      <- save the caller's rsp
sub rsp, 8                                   (pad)
<evaluate and push the arguments>
pop rdi ; pop rsi ; pop rdx
call target
mov rsp, [rsp + padBytes + mStack*8]        <- restore, at a FIXED offset
```

`IR_ALLOCA` is `sub rsp, rax`. An alloca evaluated between the `push r11` and
the `call` therefore lowers rsp by a run-time amount the restore's constant
offset does not know about, so `[rsp + off]` reads the wrong qword — in
practice, bytes the program just wrote into the alloca'd hole.

The comment on `IR_ALLOCA` said the opposite: *"call sequences align rsp
dynamically and address args relative to the moved rsp, so they are
unaffected."* Corrected in the same commit as the frontend fix.

## Repro (before the frontend hoist)

`strcpy(alloca(strlen(s) + 1), s)` — busybox `libbb/getopt32.c:373`, verbatim.
Control left for `asctime_r + 1019`, three bytes into a seven-byte instruction,
with `rsp = 0x460ac0` (a .data address). No diagnostic, no fault at the site,
and a backtrace naming a function the program never calls.

## What is fixed and what is not

`cparser.inc`'s `CHoistAllocaArgs` lifts each `AN_ALLOCA` in a call's argument
list into a temporary evaluated *before* the call — the same arrangement gcc
reaches from the same constraint. C leaves argument evaluation order
unspecified, so this picks one of the orders the standard already permits.
That closes every shape busybox reaches, and `AN_ALLOCA` is produced only by
the C frontend (the `alloca`/`__builtin_alloca` builtin and VLA lowering), so
no other language can reach the backend bug today.

Three shapes deliberately bypass the hoist, because hoisting them would be
wrong or would change semantics, and they still corrupt rsp:

- an alloca inside a **statement expression** in an argument —
  `f(({ for (...) { p = alloca(4); } p; }))` allocates once per iteration, and
  hoisting it out of the loop would allocate once;
- an alloca in a **ternary arm** or behind `&&` / `||` in an argument —
  hoisting makes an allocation and its size expression's side effects
  unconditional;
- an alloca in the **callee expression** of an indirect call.

## The real fix

Stop restoring rsp from an offset that arithmetic below it can move. The two
arrangements real compilers use are a pre-computed outgoing-argument area
(gcc's `ACCUMULATE_OUTGOING_ARGS`, no pushes during a call sequence), or a
saved-rsp slot addressed from **rbp** with one slot per static call-nesting
depth, reserved only in functions that contain an alloca. Either removes the
frontend's obligation and the three holes above with it.

Not urgent: no reachable program hits the remaining shapes today. It is filed
because the invariant the frontend now upholds is invisible from the backend,
and the next frontend to emit `IR_ALLOCA` will not know it exists.

## See also

`IR_ALLOCA` is x86-64 only; the other backends refuse it at codegen
(`target aarch64: IR op not yet supported: alloca`). Porting it is what the
aarch64 half of [[feature-c-corpus-busybox-applet]] needs, and whatever lands
there must not repeat this arrangement.

> **STALE, 2026-08-31** — aarch64 got `IR_ALLOCA` the same day and inherited the
> identical exposure; i386, arm32 and riscv32 are the three that still refuse
> it ([[feature-a-port-alloca-to-i386-arm32-and-riscv32]]). Left in place
> because rewriting a record falsifies it; the correction is what to read.


## 2026-08-31 — it is NOT only argument lists

The call sequence's saved-rsp slot is one victim; the value model's push/pop
expression stack is another, and the frontend hoist does not cover it.

```c
long a = 100;
long b = a + (long)(size_t)(alloca(32) != 0);   /* gcc: 101 */
```

pxx: **140722091760129**. `a` was pushed, the alloca lowered rsp, and the `pop`
that should have read `a` back read the alloca'd hole instead. Same mechanism
as the call sequence, different fixed-offset-from-rsp consumer — which is the
argument for fixing this in the backend rather than growing the hoist a second
time.

**But nothing reachable is broken.** All eight realistic shapes are
byte-identical to gcc, measured at `d7df19543`: declaration-with-initializer,
plain assignment, pointer arithmetic on the result, assignment through a struct
field, as a call argument, inside a loop (three iterations, each allocation
distinct and live), in a ternary arm, and two allocas in one declaration. The
failing shape needs a value already on the expression stack *and* an alloca in
the same expression *and* no call boundary between them, which is why it took a
contrived binop to produce.

So: real, measured, and not urgent. The fix is the same one the section above
names — stop addressing anything from an rsp that alloca can move.

## Porting note for the other backends

aarch64 unwinds correctly already (`mov x29, sp` before the frame reserve,
`mov sp, x29` in the epilogue, locals addressed off x29), and it manages
expression temps with explicit `str x0,[sp,#-16]!` / `ldr x0,[sp],#16` — the
same fixed-offset-from-sp exposure. A port must either keep the frontend's
invariant or fix the model; it must not assume the arrangement is safe because
the epilogue is.


## 2026-08-31 — RESOLVED in the backends, and the ticket was wrong about three shapes

Fixed as one group with the aarch64 half, which had inherited the identical
exposure when it got IR_ALLOCA earlier the same day.

**The model.** A body containing an IR_ALLOCA reserves one frame qword, the
ALLOCA BASE, holding where its expression stack starts -- the stack pointer at
every point where nothing is pushed. An alloca lowers sp by the 16-rounded
size, relocates everything between sp and the base down by that amount, and
returns the gap that opens up under the base. The region moves as a unit, so
every sp-relative offset into it is preserved and no push, pop or fixed-offset
argument slot has to know an alloca happened. Successive allocas stack downward
under the frame; the epilogue unwinds them all at once.

Relocation cannot fix a saved ABSOLUTE stack pointer, whose bytes move while its
value does not, and an expression holds exactly one: the caller's rsp that
x86-64's call sequence parks below its outgoing argument area. So in an
alloca-bearing body those sites save `rsp - base` and restore `base + delta`.
**aarch64 needs no counterpart** -- its call sequence reads its argument temps
at fixed offsets from sp and drops them with a relative `add sp, sp, #imm`, so
it never parks an absolute sp at all.

Bodies with no IR_ALLOCA emit byte-identical code to before, which is every
Pascal body -- so **the self-host fixedpoint is not evidence about this change**
in either direction. The C differentials are.

**Deliberately not covered:** a statement-level scratch area addressed through a
saved absolute pointer -- IR_EXC_ENTER's exception frame (whose head is
published to BSS_EXC_TOP) and the shortstring concat buffer. Relocation moves
those bytes and leaves the pointer behind. Neither is reachable with an alloca
today: both are Pascal constructs and IR_ALLOCA is produced only by the C
frontend, which has no try/except and no shortstrings. Recorded at the site.

### The correction: the three "still broken" shapes were not broken

The section above says three shapes bypass the hoist and *still corrupt rsp* --
statement expression in an argument, ternary/`&&`/`||` in an argument, and the
callee expression of an indirect call. The first half is true: the whitelist in
`CReplaceAllocasWithTemps` does skip all three, so the hoist genuinely does not
reach them. The second half does not reproduce. Four constructions of those
shapes, including two inside an EXTERNAL call's argument list and one on the
stack-argument path, **all matched gcc BEFORE the fix**, on x86-64 and aarch64.

Disassembling the ternary case says why the premise fails: the alloca's
`sub %rax,%rsp` is emitted 99 bytes BEFORE the call sequence's
`and rsp,-16 ; push r11`, so the saved rsp is taken *after* the alloca has
already moved it. "Not hoisted" was read as "reaches the backend bug", and those
are different claims.

So the fix removes the class; it did not close three open shapes, and nothing
here claims it did. The rows are in the test anyway, because the whitelist that
skips them is still there and a future emitter reordering could make the premise
true.

### Measured

18 shapes, each also built as its own program so no shape can mask another,
differentially against `gcc -O0`:

| binary | result |
| --- | --- |
| `f92c42a69850` (pre-fix HEAD, x86-64) | 17 of 18 match; shape 9 returns the hole |
| `357155e0ce35` (x86-64 fixed) | 18 of 18 |
| `357155e0ce35` (aarch64 still unfixed) | 17 of 18; shape 9, identical symptom |
| `452bbd933dc1` (both fixed) | 18 of 18, x86-64 and under qemu-aarch64 |

`test/c_vla.c` and `test/c_alloca_in_call_argument.c` still pass on both
targets. The regression test is `test/c_alloca_expression_stack.c`, in
`test-core`.

**One control that lied, worth recording:** the first baseline used the PINNED
compiler (`992065f21f33`, 2026-08-27) because it was to hand, and it segfaulted
on the combined program at shape 5 -- which reads as a much bigger bug than the
one being fixed. It is an older defect already fixed between the pin and HEAD;
the pre-fix HEAD binary runs all 14 shapes to completion. A control has to be
the commit under test, not the nearest binary lying around.

### For the port

[[feature-a-port-alloca-to-i386-arm32-and-riscv32]] must carry this model, not
the old one. Its template section still describes the five-instruction aarch64
version and says the frontend upholds the invariant; that is now stale. The
question a port has to answer FIRST is not whether the epilogue unwinds -- it is
**where that backend's expression temps live, and whether it ever stores an
absolute stack pointer**. i386 has the x86-64 shape (push/pop temps AND a saved
absolute esp in its call sequence, so it needs both halves); arm32 and riscv32
need checking against the aarch64 question.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
