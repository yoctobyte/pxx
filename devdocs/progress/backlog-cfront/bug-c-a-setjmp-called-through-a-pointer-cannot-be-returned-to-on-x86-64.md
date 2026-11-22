---
slug: bug-c-a-setjmp-called-through-a-pointer-cannot-be-returned-to-on-x86-64
track: C
prio: 30
type: bug
status: backlog
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

micropython's native emitter keeps `setjmp` in its function table
(py/nativeglue.c), and JIT-generated code calls it through that table. In C,
this shape is rare. test/c_setjmp_as_value.c names this ticket and leaves the
shape out.
