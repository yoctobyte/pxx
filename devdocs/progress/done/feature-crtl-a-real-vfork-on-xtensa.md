---
track: ESP
tags: [crtl, xtensa, vfork, gibux, nommu]
prio: 20
type: feature
blocked-by: []
summary: "On xtensa (posix), vfork() is a real vfork: clone(CLONE_VM|CLONE_VFORK|SIGCHLD = 0x4111, 0, 0, 0, 0), from a frameless body the compiler emits (EmitCVforkStub, cparser.inc), after uClibc's xtensa vfork.S. crtl's system() and popen() use it on xtensa. Gibux on the ESP32-S3 has no MMU, so fork fails with ENOMEM and busybox NOMMU calls vfork itself."
status: done
owner: unassigned
---

# A real vfork on xtensa

## Why the body has no frame
A vfork child shares the parent's stack and returns into the caller. A C wrapper's frame sits below the caller's sp, and the child's next calls overwrite it. The parent then returns through it: on windowed, retw does a window underflow from that same area. So the body can't own any stack:
- **Windowed:** there is no `entry`, so the body runs in the caller's window.
  - call8 left the return address in a8. a2..a6 are parked in a11..a15 across the syscall, and the result goes to a10.
  - The return is retw's arithmetic done by hand: the low 30 bits of a8, under the PC's top 2 bits, which come from a call0 to the next word. Then jx.
- **Call0:** syscall, then ret. Every register the call touches is caller-saved.

## Callers
- crtl's `vfork()` on other targets is still `fork()`.
- On xtensa, system() and popen() call vfork. Their children only dup2, close and exec.
- fork(), daemon() and forkpty() still fork, and fail on Gibux as they must.
- The Pascal runtime's PalBackendFork and the spawn helper (subprocess) still use clone(SIGCHLD). That is a separate piece of work if Pascal programs need to spawn processes on Gibux.

## Test
tools/check_xtensa_vfork.py runs test/c_xtensa_vfork.c two ways:
- **Call0,** as a hosted program. It must print "vfork check 77 system 5".
- **Windowed,** as an object linked with test/c_xtensa_windowed_start.S. It must exit 77.

qemu runs a vfork as a fork, so the program's results can't tell the two apart. Instead the checker requires CLONE_VM|CLONE_VFORK on every clone in `qemu -strace`. The old compiler fails here with `clone(0x11)`.
