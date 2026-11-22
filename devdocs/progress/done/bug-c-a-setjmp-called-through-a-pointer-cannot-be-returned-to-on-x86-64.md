---
slug: bug-c-a-setjmp-called-through-a-pointer-cannot-be-returned-to-on-x86-64
track: C
prio: 20
type: bug
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, setjmp, x86-64]
blocked-by: []
summary: "`int (*f)(jmp_buf) = setjmp; if (f(jb) == 0) longjmp(jb, 5);` segfaults on x86-64 after the longjmp (gcc: returns 5). i386, aarch64, arm32 and riscv32 are right. The indirect call realigns the stack and keeps the old rsp in a slot below the caller's frame; the longjmp comes back to the instruction that reloads rsp from that slot, which later calls have overwritten."
---

# A setjmp called through a pointer cannot be returned to on x86-64

## Repro

```c
#include <stdio.h>
#include <setjmp.h>
static jmp_buf jb;
int main(void) {
  int (*f)(jmp_buf) = setjmp;
  int r = f(jb);
  printf("r=%d\n", r);
  if (r == 0) longjmp(jb, 5);
  return 0;
}
```

gcc prints `r=0` then `r=5`. pxx x86-64 prints `r=0`, then segfaults with rsp
pointing into .text.

## What the call site does

From `--emit-obj` + objdump, the indirect call in main is

```
mov    %rsp,%r11
and    $0xfffffffffffffff0,%rsp
push   %r11              ; old rsp, BELOW main's frame
sub    $0x8,%rsp
...
call   *%r11
mov    0x8(%rsp),%rsp    ; reload old rsp from that slot
```

setjmp records the rsp and return address of this call. When longjmp comes
back, it lands on `mov 0x8(%rsp),%rsp`. By then printf's call has reused that
stack slot, so rsp is loaded from garbage. A direct `setjmp(env)` is the
`__pxx_setjmp` intrinsic and does not go through this sequence. The other
targets keep a fixed frame and are fine.

Plausible fix: an indirect call whose frame is already 16-aligned at that point
(the usual case) should not realign at run time. Or the old rsp could go in a
slot inside the caller's frame, which a later call cannot reach.

## Who needs it

No known user on x86-64. micropython's function table does hold `setjmp`
(py/nativeglue.c), but only the xtensawin emitter calls it (N_NLR_SETJMP).
The x86-64 JIT calls the table's nlr_push entry and needs py/nlrx64.c, see
feature-c-attribute-naked-and-inline-asm-branches-to-symbols. An earlier
version of this ticket blamed micropython's seven native/viper test
failures on this bug. That was wrong: they came from building with
-DMICROPY_NLR_SETJMP=1, where the x86-64 JIT calls nlr_push_tail and never
saves its registers. In C, this shape is rare. test/c_setjmp_as_value.c
names this ticket and leaves the shape out.

## Done (2026-11-22)

The second fix the ticket suggested. A C program's x86-64 IR_CALL_IND now
gets a frame slot (IRCallRspSlot, allocated with the call node by
IRCallKeepRsp). The call sequence stores the caller's rsp there as well as
below the argument area, and restores rsp from the frame slot after the
call. A second return through longjmp finds the slot intact, because it is
in the caller's frame. In a body with alloca the slot holds `rsp - base`,
as the parked copy did. Pascal bodies are unchanged; the switch is
CProgramMode. The cost is one store and one 8-byte slot per indirect call
site.

Direct calls keep the old sequence. A direct setjmp is the intrinsic. A
returns-twice function called directly by name (vfork, getcontext) has not
been measured.

Test c_setjmp_through_pointer (gcc-checked: x86-64, i386, aarch64) covers
four returns through one pointer-called setjmp, plus alloca in the same
body, indirect calls nested in arguments, and a loop of them.
