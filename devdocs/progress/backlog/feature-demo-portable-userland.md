---
prio: 55  # auto — flagship showcase of the ir-as-substrate + PAL thesis; also a NilPy forcing function
---

# PXX portable userland (mini OS-personality) — one shell, any kernel

- **Type:** feature — **Track E** (Examples/apps; file-ownership **Track B** —
  `examples/**` / app dir / `lib/**`, plus the NilPy-frontend deps below which
  are Track A). Umbrella / demo arc.
- **Status:** backlog — filed 2026-07-10.
- **Opened:** 2026-07-10 (design-thesis session — the PAL seam paying off).
- **Owner:** —

## The idea (one line)
**PXX supplies the userland the kernel deliberately leaves out.** The "kernel"
below is just an ABI — Linux (syscalls) or FreeRTOS (tasks/IPC). The **PAL**
([[feature-platform-abstraction-layer]], landed) is the seam that swaps them, so
**one shell/app source runs as Linux PID 1, on ESP32/FreeRTOS, or as a desktop
process** — swap the PAL backend, not the app. This is the ir-as-substrate thesis
made visible: thin frontend + shared IR + one platform seam ⇒ the app is
kernel-agnostic by construction, not by luck.

## Backends (the same userland, three kernels)
- **Linux `/init`** — [[feature-kernel-matrix-bootroom]] (rainy-day) already has
  this: static x86-64 ELF, raw syscalls only, `init=/init`, PID-1-safe, no
  libc/coreutils/systemd. "Throw away the distro userland." This umbrella adopts
  bootroom as the Linux backend (leave it rainy-day; link it here so it stops
  reading as an orphan stunt).
- **ESP32 / FreeRTOS** — the memory-constrained variant. FreeRTOS is a preemptive
  RTOS *kernel* (scheduler + IPC), no processes/MMU/FS — exactly the userland gap
  the shell fills. Applets = FreeRTOS tasks (`xTaskCreate`); pipes = stream
  buffers (blocking read ⇒ natural backpressure + concurrency, no hand-coded
  yields). IDF path already exists ([[project_esp_idf_isr_2026_06_21]], ESP
  threading).
- **Desktop process** — normal x86-64/aarch64 binary for fast edit-run dev; pipes
  map to real threads/pipes. Same source, same shape.

## Flagship app — the NilPy shell (busybox/applet model)
A Unix-ish shell written in **NilPy** (Nil-Python): line editor → parse →
applet dispatch → `a | b | c`. No `fork`/`exec` (no MMU on classic ESP32): one
binary, commands are built-in applet functions dispatched by name
(`echo cat ls grep wc head tail ps`), optionally run as tasks. A VFS gives the
filesystem illusion (borrow from the sqlite file-VFS + PAL groundwork).

Why NilPy: it doubles as a **frontend forcing function** — the shell drags NilPy
from "proven toy" (classes, control flow, auto-typing, C-import binding all work)
to a real language, one concrete feature at a time. And it demos the cross-target
thesis at the *concurrency* level (preemptive tasks on ESP, threads on desktop).

## Real dependencies (NilPy frontend gaps the shell forces — Track A)
- **[[feature-nilpy-collections-and-string-methods]]** — `list`/`dict` (argv,
  env, job table) + string methods (`split`/`join`/`strip` for parsing). The
  hard blocker; file/advance this first.
- exceptions + a file-I/O API surface (redirects) — smaller, follow-on.

## Phasing
1. **Desktop-first, NilPy**: shell loop + parse + applet dispatch + `a|b` via
   buffers, on x86-64. Surfaces the collection/string gaps → drive them.
2. **Applet set**: `echo cat ls grep wc head tail ps` over a VFS abstraction.
3. **Cross to ESP**: desktop PAL → IDF PAL; applets as FreeRTOS tasks; pipes as
   stream buffers.
4. **Polish**: history, redirects, `&` background = spare task.

## Gate (file-ownership Track B for the app; Track A for the NilPy deps)
App/demo builds with `$(PXX_STABLE)` (Track B rule — never rebuild the compiler);
`make lib-test` / `demos` green; desktop shell runs; ESP variant boots under the
QEMU/IDF harness. NilPy-frontend deps carry Track A's gate (self-host
byte-identical) since they touch shared frontend/RTL.

## Links
[[feature-platform-abstraction-layer]] (the seam) · [[feature-kernel-matrix-bootroom]]
(Linux backend) · [[feature-nilpy-collections-and-string-methods]] (blocker) ·
[[project_nil_python_arc]] · thesis `devdocs/dev/ir-as-substrate.md`.
