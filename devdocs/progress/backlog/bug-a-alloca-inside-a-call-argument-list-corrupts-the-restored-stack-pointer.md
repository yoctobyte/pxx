---
track: A
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "x86-64's call sequence restores the caller's rsp from a FIXED offset below the outgoing argument area; alloca() moves rsp, so an alloca evaluated during argument evaluation shifts that slot out from under the restore and rsp comes back holding the alloca'd bytes. The C frontend now hoists allocas out of argument lists (af26fa968+), which covers every shape busybox reaches, but the BACKEND invariant is undocumented and three shapes still bypass the hoist."
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
