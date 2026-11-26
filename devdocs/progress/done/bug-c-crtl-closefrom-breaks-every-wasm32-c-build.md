---
title: "crtl closefrom's SYS_close_range broke every wasm32 C build"
status: done
owner: claude-dupwt
prio: 70
area: crtl
---

closefrom (lib/crtl/src/unistd.c, added for dhcpcd in 21474a814c) calls
syscall(SYS_close_range, ...). wasm32 has no syscall numbers, and crtl's
unistd.c is part of every C program's runtime. So every wasm32 C compile
failed with `undeclared identifier 'SYS_close_range'`. test-core found it
at b240f77f68 in five rows: c_va_arg_every_target,
c_int_signedness_every_target, and c_wasm32_{hosted_stdio,math_h,fsinit}.
The call is now under `#ifdef SYS_close_range`; without it, closefrom
uses the close loop alone.
